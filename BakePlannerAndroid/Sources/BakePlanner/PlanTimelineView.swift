import BakePlannerCore
import SwiftUI

/// The planned steps of every plan, plan by plan in the order they begin:
/// each step with its time, moved with a tap on it, done with "Erledigt";
/// a whole plan removed after asking. Steps the rhythm queued ahead of time show up two days before
/// they are due, as on the iPhone.
struct PlanTimelineView: View {
    let model: AppModel
    /// The plan waiting for the user to confirm its removal. Kept apart from
    /// the dialog's visibility: Android closes the dialog before it runs
    /// the chosen button.
    @State var planToDelete: TimelinePlan?
    @State var confirmsDeletion = false
    /// The step being moved. Kept apart from the sheet's visibility, as the
    /// dialogs are.
    @State var stepToShift: StoredScheduledStep?
    @State var shiftsStep = false
    @State var showsShiftError = false
    /// The plan the bake mode shows, nil for all. Kept apart from the
    /// sheet's visibility, as the dialogs are.
    @State var bakeModePlanKey: String?
    @State var showsBakeMode = false
    /// The step whose component's ingredients are shown. Kept apart from
    /// the sheet's visibility, as the dialogs are.
    @State var ingredientStep: StoredScheduledStep?
    @State var showsIngredients = false
    /// The step whose details are shown. Kept apart from the sheet's
    /// visibility, as the dialogs are.
    @State var detailStep: StoredScheduledStep?
    @State var showsDetail = false
    @State var confirmsDeleteAll = false
    /// Refreshed every minute, so the "Als Nächstes" card moves on with time.
    @State var now = Date()
    @Environment(\.colorScheme) var colorScheme

    /// One plan: the steps of one planning run.
    struct TimelinePlan: Identifiable {
        let id: String
        let recipeName: String
        let steps: [StoredScheduledStep]
    }

    /// Which plan a step belongs to. Steps planned before plans had an id
    /// belong together by recipe.
    static func planKey(of step: StoredScheduledStep) -> String {
        step.data.planID?.uuidString ?? "recipe:" + step.data.recipeName
    }

    private var plans: [TimelinePlan] {
        let visible = model.scheduledSteps.filter { $0.data.isVisible() }
        var order: [String] = []
        var grouped: [String: [StoredScheduledStep]] = [:]
        for step in visible {
            let key = Self.planKey(of: step)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(step)
        }
        return order.compactMap { key in
            guard let steps = grouped[key], let first = steps.first else { return nil }
            return TimelinePlan(id: key, recipeName: first.data.recipeName, steps: steps)
        }
    }

    var body: some View {
        let plans = self.plans
        return ZStack {
            LinearGradient(colors: [Palette.backgroundTop(colorScheme), Palette.backgroundBottom(colorScheme)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if plans.isEmpty {
                VStack(spacing: 12) {
                    Text("Keine geplanten Schritte")
                        .font(.title2)
                        .foregroundStyle(Palette.accent(colorScheme))
                    Text("Öffne ein Rezept und tippe auf „Planen“.")
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List {
                    // The one step that matters right now, as the iPhone's
                    // "Als Nächstes" bar in the main menu.
                    if let current = currentStep {
                        Section {
                            NextStepCard(step: current, now: now)
                        }
                    }
                    ForEach(plans) { plan in
                        Section {
                            ForEach(plan.steps, id: \.key) { step in
                                HStack(alignment: .top, spacing: 8) {
                                    // A tap opens the step's details, as on the
                                    // iPhone; moving it is offered there.
                                    Button {
                                        detailStep = step
                                        showsDetail = true
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(verbatim: PlanText.dateTime(step.data.date))
                                                .font(.caption)
                                                .foregroundStyle(step.data.date < now ? Color.red : Color.secondary)
                                            Text(verbatim: step.data.instruction)
                                                .foregroundStyle(Color.primary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.borderless)
                                    // The ingredients of the component this step mixes,
                                    // as the iPhone's "i" on the card.
                                    if component(of: step) != nil {
                                        Button {
                                            ingredientStep = step
                                            showsIngredients = true
                                        } label: {
                                            Image(systemName: "info.circle")
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel(Text("Zutaten"))
                                    }
                                    Button("Erledigt") {
                                        model.markDone(step)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            Button {
                                bakeModePlanKey = plan.id
                                showsBakeMode = true
                            } label: {
                                Label("Backmodus starten", systemImage: "play.fill")
                            }
                            Button("Geplante Schritte löschen", role: .destructive) {
                                planToDelete = plan
                                confirmsDeletion = true
                            }
                        } header: {
                            Text(verbatim: plan.recipeName)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Geplante nächste Schritte")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    bakeModePlanKey = nil
                    showsBakeMode = true
                } label: {
                    Label("Backmodus starten", systemImage: "play.fill")
                }
                .disabled(plans.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    confirmsDeleteAll = true
                } label: {
                    Label("Alle löschen", systemImage: "trash")
                }
                .disabled(plans.isEmpty)
            }
        }
        .appSheet(isPresented: $showsDetail) {
            if let step = detailStep {
                NavigationStack {
                    StepDetailSheet(step: step, component: component(of: step), onShift: {
                        // The shift sheet opens once this one has gone.
                        stepToShift = step
                        Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            shiftsStep = true
                        }
                    }, onDone: {
                        model.markDone(step)
                    })
                }
            }
        }
        .appSheet(isPresented: $showsIngredients) {
            if let step = ingredientStep, let component = component(of: step) {
                NavigationStack {
                    StepIngredientsSheet(step: step, component: component)
                }
            }
        }
        .alert("Alle löschen", isPresented: $confirmsDeleteAll) {
            Button("Löschen", role: .destructive) {
                // Every step of every plan, those not shown yet included.
                model.deletePlan(model.scheduledSteps)
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Alle Pläne und ihre Erinnerungen werden entfernt.")
        }
        .task {
            // Once a minute, so the card and the red times move with the clock.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = Date()
            }
        }
        .appSheet(isPresented: $showsBakeMode) {
            NavigationStack {
                BakeModeView(model: model, planKey: bakeModePlanKey)
            }
        }
        .task {
            model.loadScheduledSteps()
        }
        .appSheet(isPresented: $shiftsStep) {
            if let step = stepToShift {
                NavigationStack {
                    StepShiftSheet(step: step) { minutes, includeFollowing in
                        Task {
                            if await model.shift(step, byMinutes: minutes, includeFollowing: includeFollowing) == .dateInPast {
                                showsShiftError = true
                            }
                        }
                    }
                }
            }
        }
        .alert("Verschieben nicht möglich", isPresented: $showsShiftError) {
            Button {
            } label: {
                Text(verbatim: "OK")
            }
        } message: {
            Text("Der verschobene Zeitpunkt muss in der Zukunft liegen.")
        }
        .alert("Bist Du sicher?", isPresented: $confirmsDeletion) {
            Button("Löschen", role: .destructive) {
                if let plan = planToDelete {
                    // Every step of the plan, those not shown yet included.
                    model.deletePlan(model.scheduledSteps.filter { Self.planKey(of: $0) == plan.id })
                }
                planToDelete = nil
            }
            Button("Abbrechen", role: .cancel) {
                planToDelete = nil
            }
        } message: {
            if let plan = planToDelete {
                Text(verbatim: plan.recipeName)
            }
        }
    }
}

extension PlanTimelineView {
    /// The step due within the last hour, else the next one ahead — the rule
    /// of the iPhone's card, widget and bake mode (CurrentStepRule).
    var currentStep: StoredScheduledStep? {
        let visible = model.scheduledSteps.filter { $0.data.isVisible(at: now) }
        return CurrentStepRule.currentStep(in: visible, at: now, date: { $0.data.date })?.step
    }

    /// The component a step mixes, when its recipe is on the device and
    /// the step names one of its components.
    func component(of step: StoredScheduledStep) -> ComponentColumn? {
        guard let recipe = model.recipes.first(where: { $0.content.name == step.data.recipeName })?.content,
              let component = BakeModeText.component(of: step.data, in: recipe),
              !component.ingredients.isEmpty else { return nil }
        return component
    }
}

/// "Als Nächstes" or "Jetzt fällig": the step that matters right now, with
/// how far away it is, as the iPhone's NextStepCardView.
struct NextStepCard: View {
    let step: StoredScheduledStep
    let now: Date
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let isDue = step.data.date <= now
        let minutes = max(1, Int((abs(step.data.date.timeIntervalSince(now)) / 60).rounded(.up)))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(isDue ? "Jetzt fällig" : "Als Nächstes")
                    .font(.caption)
                    .bold()
                    .textCase(.uppercase)
                Spacer()
                if isDue {
                    Text("seit \(BakeHistoryFacts.durationText(minutes))")
                        .font(.caption)
                        .bold()
                } else {
                    Text("in \(BakeHistoryFacts.durationText(minutes))")
                        .font(.caption)
                        .bold()
                }
            }
            .foregroundStyle(Palette.accent(colorScheme))
            Text(verbatim: step.data.instruction)
                .font(.headline)
            Text(verbatim: step.data.recipeName + " · " + PlanText.dateTime(step.data.date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A planned step in full: recipe, start, step number, duration and the
/// whole text, the ingredients it mixes, and the two actions of the
/// iPhone's card — the iPhone's ScheduledTaskDetailView.
struct StepDetailSheet: View {
    let step: StoredScheduledStep
    let component: ComponentColumn?
    let onShift: () -> Void
    let onDone: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Rezept")
                    Spacer()
                    Text(verbatim: step.data.recipeName)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Beginn")
                    Spacer()
                    Text(verbatim: PlanText.dateTime(step.data.date))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Schritt")
                    Spacer()
                    Text(verbatim: Rational.decimalPlace(step.data.step, 10))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Dauer")
                    Spacer()
                    Text(verbatim: Rational.displayHoursMinutes(step.data.duration))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Nächster Schritt")
            }
            Section {
                Text(verbatim: step.data.instruction)
            } header: {
                Text("Beschreibung")
            }
            if let component {
                Section {
                    ForEach(Array(BakeModeText.ingredientLines(of: component, scale: step.data.effectiveServingScale).enumerated()),
                            id: \.offset) { _, line in
                        Text(verbatim: line)
                    }
                } header: {
                    Text("Zutaten für „\(component.name)“")
                }
            }
            Section {
                Button("Schritt verschieben") {
                    onShift()
                    dismiss()
                }
                Button("Erledigt") {
                    onDone()
                    dismiss()
                }
            }
        }
        .navigationTitle("Nächster Schritt")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") {
                    dismiss()
                }
            }
        }
    }
}

/// The ingredients of the component a planned step mixes, in the amount
/// the plan was made for — the iPhone's sheet behind the "i" on a card.
struct StepIngredientsSheet: View {
    let step: StoredScheduledStep
    let component: ComponentColumn
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            Section {
                Text(verbatim: step.data.instruction)
                    .foregroundStyle(.secondary)
            } header: {
                Text(verbatim: step.data.recipeName)
            }
            Section {
                ForEach(Array(BakeModeText.ingredientLines(of: component, scale: step.data.effectiveServingScale).enumerated()),
                        id: \.offset) { _, line in
                    Text(verbatim: line)
                }
            } header: {
                Text("Zutaten für „\(component.name)“")
            }
        }
        .navigationTitle("Zutaten")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") {
                    dismiss()
                }
            }
        }
    }
}

/// Moves one planned step by some minutes, earlier or later, alone or with
/// the later steps of its plan — the iPhone's "Schritt verschieben" sheet,
/// showing the step's time before and after.
struct StepShiftSheet: View {
    let step: StoredScheduledStep
    /// Minutes (negative for earlier) and whether the following steps move too.
    let onApply: (Int, Bool) -> Void
    @State var minutesText = ""
    @State var later = true
    @State var withFollowing = false
    @Environment(\.dismiss) var dismiss

    /// The minutes typed: a whole number above zero, at most a day.
    private var minutes: Int? {
        guard let value = Int(minutesText.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return min(value, 1_440)
    }

    private var signedMinutes: Int? {
        minutes.map { later ? $0 : -$0 }
    }

    var body: some View {
        Form {
            Section {
                Text(verbatim: step.data.recipeName)
                    .font(.headline)
                Text(verbatim: step.data.instruction)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Bisher")
                    Spacer()
                    Text(verbatim: PlanText.dateTime(step.data.date))
                }
                if let signedMinutes {
                    HStack {
                        Text("Neu")
                        Spacer()
                        Text(verbatim: PlanText.dateTime(step.data.date.addingTimeInterval(TimeInterval(signedMinutes * 60))))
                            .bold()
                    }
                }
            }

            Section {
                TextField("Minuten", text: $minutesText)
                Picker("Richtung", selection: $later) {
                    Text("Früher").tag(false)
                    Text("Später").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Betroffene Schritte", selection: $withFollowing) {
                    Text("Nur dieser Schritt").tag(false)
                    Text("Alle nachfolgenden").tag(true)
                }
                .pickerStyle(.segmented)
                Text(withFollowing
                     ? LocalizedStringKey("Dieser Schritt und alle späteren Schritte desselben Plans werden um dieselbe Zeit verschoben.")
                     : LocalizedStringKey("Nur dieser Schritt wird verschoben; alle anderen Schritte des Plans bleiben, wo sie sind."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Zeitverschiebung")
            }
        }
        .navigationTitle("Schritt verschieben")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Übernehmen") {
                    if let signedMinutes {
                        onApply(signedMinutes, withFollowing)
                    }
                    dismiss()
                }
                .disabled(minutes == nil)
            }
        }
    }
}
