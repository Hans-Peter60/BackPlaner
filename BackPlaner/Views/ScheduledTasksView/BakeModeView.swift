//
//  BakeModeView.swift
//  BackPlaner
//
//  The kitchen view of a running plan: one step at a time in large type, the
//  component's ingredients where a step mixes one, big buttons for back,
//  next and done, the step read aloud on request, and a screen that stays
//  on. Made for floury hands and a phone propped against the flour tin.
//

import SwiftUI
import CoreData
import AVFoundation

struct BakeModeView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext
    // Three buttons side by side need their titles on one line each; at the
    // accessibility text sizes they stack instead.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var model: RecipeModel

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>

    private var stepsRequest: FetchRequest<NextStep>
    private var steps: FetchedResults<NextStep> { stepsRequest.wrappedValue }

    /// The step on display. Nil until the first appearance picks the one
    /// that matters now; afterwards the user's own choice.
    @State private var currentID: NSManagedObjectID?
    @State private var speaker = StepSpeaker()
    @State private var doneHaptic = false

    /// Settings → Backplanung → "Sprachausgabe im Backmodus".
    @AppStorage(AppSettingsKeys.speechInBakeMode) private var speechEnabled = AppSettings.defaultSpeechInBakeMode

    /// Narrowed to one plan when the list was filtered; otherwise every
    /// planned step.
    init(planFilter: PlanKey?) {
        stepsRequest = FetchRequest(
            entity: NextStep.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)],
            predicate: planFilter?.predicate
        )
    }

    // MARK: Which step

    private var currentIndex: Int? {
        guard let currentID else { return nil }
        return steps.firstIndex { $0.objectID == currentID }
    }

    /// The step the view opens on: the one due within the last hour, else
    /// the next one ahead, else the last of the plan — the same rule as the
    /// main-menu card and the widget.
    private func initialStep(at now: Date) -> NextStep? {
        if let due = steps.last(where: { $0.date <= now }),
           now.timeIntervalSince(due.date) < PlanSnapshot.dueGracePeriod {
            return due
        }
        return steps.first(where: { $0.date > now }) ?? steps.last
    }

    private func show(_ step: NextStep?) {
        speaker.stop()
        currentID = step?.objectID
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if let index = currentIndex, steps.indices.contains(index) {
                    stepView(steps[index], index: index)
                } else {
                    ContentUnavailableView(
                        "Keine geplanten Schritte",
                        systemImage: "calendar",
                        description: Text("Setze Erinnerungen in der Backanleitung eines Rezepts.")
                    )
                }
            }
            .warmBackground()
            .navigationTitle("Backmodus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
        .onAppear {
            // Baking takes longer than the auto-lock; the screen stays on
            // for as long as this view is up.
            UIApplication.shared.isIdleTimerDisabled = true
            if currentID == nil {
                currentID = initialStep(at: Date())?.objectID
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            speaker.stop()
        }
        // A step removed elsewhere — marked done from a reminder, say —
        // must not leave the view pointing at nothing.
        .onChange(of: steps.count) { _, _ in
            if currentIndex == nil {
                currentID = initialStep(at: Date())?.objectID
            }
        }
        .sensoryFeedback(.success, trigger: doneHaptic)
    }

    // MARK: One step

    private func stepView(_ step: NextStep, index: Int) -> some View {
        let component = component(for: step)

        return VStack(spacing: 0) {

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    header(for: step, index: index)

                    Text(step.instruction)
                        .font(Theme.brandFont(26))
                        .foregroundColor(Theme.cardTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    if let component {
                        ingredientsCard(component)
                    }
                }
                .padding()
            }

            controls(for: step, index: index, component: component)
        }
    }

    private func header(for step: NextStep, index: Int) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let isDue = step.date <= context.date

            VStack(alignment: .leading, spacing: 8) {
                // Two lines rather than one row: a recipe name like
                // "Sauerteigbrot mit Kartoffeln und Saaten" does not fit
                // beside the step counter.
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.recipeName)
                        .font(Theme.brandFont(15))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Schritt \(index + 1) von \(steps.count)")
                        .font(Theme.bodyFont(15))
                }
                .foregroundColor(Theme.subtitle)

                // Capsule and distance side by side, until the accessibility
                // sizes: there the row squeezed the capsule into two narrow
                // columns ("He / ute", "06: / 32"), so the two stack and the
                // capsule keeps its natural width.
                let timeRowLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 10))

                timeRowLayout {
                    HStack(spacing: 4) {
                        Image(systemName: isDue ? "bell.fill" : "clock.fill")
                        StepTiming.dayLabel(for: step.date, now: context.date)
                        Text(step.date, format: .dateTime.hour().minute())
                    }
                    .fixedSize()
                    .font(Theme.brandFont(17))
                    .foregroundColor(Theme.accentText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.accentText.opacity(0.12), in: Capsule())

                    Group {
                        if isDue {
                            Text("seit \(StepTiming.distanceText(from: context.date, to: step.date))")
                        } else {
                            Text("in \(StepTiming.distanceText(from: context.date, to: step.date))")
                        }
                    }
                    .font(Theme.bodyFont(17))
                    .foregroundColor(Theme.subtitle)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
            }
        }
    }

    private func ingredientsCard(_ component: ComponentColumn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zutaten für „\(component.name)“")
                .font(Theme.brandFont(17))
                .foregroundColor(Theme.title)

            ForEach(Array(component.ingredients.enumerated()), id: \.offset) { _, ingredient in
                Text(Self.ingredientLine(ingredient))
                    .font(Theme.bodyFont(20))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func controls(for step: NextStep, index: Int, component: ComponentColumn?) -> some View {
        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))

        return VStack(spacing: 12) {
            rowLayout {
                bigButton(systemImage: "chevron.left", title: "Zurück", enabled: index > 0) {
                    show(steps[index - 1])
                }
                .accessibilityLabel("Vorheriger Schritt")

                if speechEnabled {
                    bigButton(systemImage: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2.fill",
                              title: speaker.isSpeaking ? "Stopp" : "Vorlesen",
                              enabled: true) {
                        if speaker.isSpeaking {
                            speaker.stop()
                        } else {
                            speaker.speak(Self.spokenText(for: step, component: component))
                        }
                    }
                    .accessibilityLabel(speaker.isSpeaking ? "Vorlesen beenden" : "Schritt vorlesen")
                }

                bigButton(systemImage: "chevron.right", title: "Weiter", enabled: index + 1 < steps.count) {
                    show(steps[index + 1])
                }
                .accessibilityLabel("Nächster Schritt")
            }

            Button {
                markDone(step, at: index)
            } label: {
                // Not a `Label`: inside the prominent button its title kept
                // to one line and the French "Marquer comme terminé" ended
                // as "Marquer com…" at the accessibility sizes. A plain
                // stack lets the title wrap.
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                    Text("Erledigt")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .lineLimit(nil)
                .font(Theme.brandFont(18))
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentTop)
            // The checkmark symbol would make VoiceOver add "selected".
            .accessibilityRemoveTraits(.isSelected)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.thinMaterial)
    }

    private func bigButton(systemImage: String, title: LocalizedStringKey, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(Theme.bodyFont(13))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .tint(Theme.accentText)
        .disabled(!enabled)
    }

    // MARK: Actions

    /// Removes the step and its reminder, then moves on to the step that
    /// follows it — or back to the one before, at the end of the plan.
    private func markDone(_ step: NextStep, at index: Int) {
        speaker.stop()

        let successor: NextStep? = index + 1 < steps.count
            ? steps[index + 1]
            : (index > 0 ? steps[index - 1] : nil)

        NotificationActions.cancelPendingNotification(for: step)
        managedObjectContext.delete(step)
        do {
            try managedObjectContext.save()
            doneHaptic.toggle()
        } catch {
            managedObjectContext.rollback()
            AppLog.persistence.error("Could not mark step done in bake mode")
            return
        }

        currentID = successor?.objectID
    }

    // MARK: Helpers

    private func component(for step: NextStep) -> ComponentColumn? {
        if let recipe = recipes.first(where: { $0.name == step.recipeName }) {
            return ScheduledStepComponent.column(for: recipe, step: step.step, instructionText: step.instruction)
        }
        if let recipeFB = model.recipesFB.first(where: { $0.name == step.recipeName }) {
            return ScheduledStepComponent.column(for: recipeFB, step: step.step, instructionText: step.instruction)
        }
        return nil
    }

    private static func ingredientLine(_ ingredient: TotalIngredientData) -> String {
        "• " + Rational.getPortion(unit: ingredient.unit,
                                   weight: ingredient.weight,
                                   num: ingredient.numerator,
                                   denom: ingredient.denominator,
                                   targetServings: AppSettings.storedServingSize)
            + ingredient.name
    }

    /// What the speaker says: the step, then the ingredients if there are
    /// any, as sentences rather than bullet points.
    private static func spokenText(for step: NextStep, component: ComponentColumn?) -> String {
        var parts = [step.instruction.replacingOccurrences(of: "\n", with: ". ")]
        if let component, !component.ingredients.isEmpty {
            let heading = String(
                format: String(localized: "Zutaten für „%@“:", bundle: AppSettings.localizationBundle, locale: AppSettings.locale),
                component.name
            )
            let lines = component.ingredients.map { ingredient in
                // Spelled out: "TL" or "tsp" read aloud is just letters.
                Rational.getPortion(unit: ingredient.unit,
                                    weight: ingredient.weight,
                                    num: ingredient.numerator,
                                    denom: ingredient.denominator,
                                    targetServings: AppSettings.storedServingSize,
                                    unitStyle: .name)
                    + ingredient.name
            }
            parts.append(heading)
            parts.append(lines.joined(separator: ". "))
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Timing text

/// Shared wording for "when" a step is, used by the main-menu card and the
/// bake mode.
enum StepTiming {

    /// "17 Min.", "2 Std., 15 Min." or "1 Tag, 3 Std." — never seconds.
    static func distanceText(from now: Date, to date: Date) -> String {
        let seconds = max(60, abs(date.timeIntervalSince(now)).rounded(.up))
        // The in-app language, not the device's: `formatted` does not see the
        // locale SwiftUI carries in its environment.
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.days, .hours, .minutes],
                   width: .abbreviated,
                   maximumUnitCount: 2)
            .locale(AppSettings.locale)
        )
    }

    /// "Heute", "Morgen", or the short date for anything further away.
    static func dayLabel(for date: Date, now: Date) -> Text {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return Text("Heute")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return Text("Morgen")
        }
        return Text(date, format: .dateTime.day().month())
    }
}

// MARK: - Speech

/// Reads a step aloud in the app's language. Plays through the speaker even
/// with the ring switch muted, since the point is to be heard across the
/// kitchen, and ducks other audio while it talks.
///
/// Main-actor isolated: the view drives it, and AVSpeechSynthesizerDelegate is
/// Sendable, which a plain class with mutable state cannot be. The delegate
/// callbacks arrive on the synthesizer's own queue and hop over.
@MainActor
@Observable
final class StepSpeaker: NSObject, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        stop()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Self.voiceLanguage)
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    /// The BCP 47 tag of the in-app language; falls back to German, the
    /// app's source language, for anything else.
    private static var voiceLanguage: String {
        switch AppSettings.locale.language.languageCode?.identifier {
        case "en": return "en-US"
        case "fr": return "fr-FR"
        default:   return "de-DE"
        }
    }

    private func finished() {
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }
}
