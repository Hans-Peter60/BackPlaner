import BakePlannerCore
import SwiftUI

/// What the stopwatch records say the steps really take, next to what the
/// dish has, to take over in one tap (the iPhone's LearnedTimesView). An
/// example is not the cook's to change: its learned times go into a copy.
struct LearnedTimesView: View {
    let dish: KitchenDish
    let suggestions: [KitchenTimeLearning.Suggestion]
    let onApply: (KitchenDish) -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    private var isExample: Bool { dish.source == .sample }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(suggestions, id: \.taskID) { suggestion in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.name)
                            HStack(spacing: 6) {
                                Text(minutesText(suggestion.handsBefore, suggestion.unattendedBefore))
                                    .foregroundStyle(.secondary)
                                Text(verbatim: "→")
                                    .foregroundStyle(.secondary)
                                Text(minutesText(suggestion.hands, suggestion.unattended))
                                    .foregroundStyle(Palette.accentText(colorScheme))
                                Spacer()
                                Text(String(localized: "aus \(suggestion.runs) Durchgängen", bundle: .module))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.footnote)
                        }
                    }
                } footer: {
                    Text(String(localized: "Der Mittelwert (Median) der abgehakten Zeiten aus den letzten bis zu fünf Durchgängen. Bei Töpfen und Ofenschritten bleibt die Handarbeit, die Zeit allein passt sich an.", bundle: .module))
                }
            }
            .navigationTitle(String(localized: "Gemessene Zeiten", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Abbrechen", bundle: .module)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isExample ? String(localized: "Als eigenes Gericht", bundle: .module)
                                     : String(localized: "Übernehmen", bundle: .module)) {
                        let learned = KitchenTimeLearning.applying(suggestions, to: dish)
                        onApply(isExample ? learned.duplicate() : learned)
                        dismiss()
                    }
                }
            }
        }
        .tint(Palette.accent(colorScheme))
    }

    /// "4 Min." or "1 + 13 Min." for hands and unattended minutes.
    private func minutesText(_ hands: Int, _ unattended: Int) -> String {
        unattended > 0
            ? String(localized: "\(hands) + \(unattended) Min.", bundle: .module)
            : String(localized: "\(hands) Min.", bundle: .module)
    }
}

/// The cooking history in figures: how often, how many dishes, the stars,
/// against the plan, the last twelve months, the dishes cooked most.
struct CookStatisticsView: View {
    let runs: [KitchenCookRun]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let statistics = KitchenCookStatistics(runs: runs)
        let highest = max(1, statistics.months.map { $0.count }.max() ?? 1)
        return List {
            Section {
                LabeledContent(String(localized: "Gekocht", bundle: .module)) { Text("\(statistics.total)") }
                LabeledContent(String(localized: "Verschiedene Gerichte", bundle: .module)) { Text("\(statistics.dishCount)") }
                if let average = statistics.averageRating {
                    LabeledContent(String(localized: "Sterne im Schnitt", bundle: .module)) {
                        Text(IngredientDraft.text(for: (average * 10).rounded() / 10))
                    }
                }
                if let over = statistics.averageMinutesOverPlan {
                    LabeledContent(String(localized: "Gegen den Plan", bundle: .module)) {
                        Text(againstPlan(over))
                            .foregroundStyle(over >= 0.5 ? Palette.danger(colorScheme) : Palette.good(colorScheme))
                    }
                }
            }
            Section(String(localized: "Die letzten zwölf Monate", bundle: .module)) {
                // Bars of our own: Swift Charts is not on Android.
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(statistics.months, id: \.id) { month in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.accent(colorScheme))
                                .frame(height: max(2, 110 * Double(month.count) / Double(highest)))
                            Text(month.month.formatted(.dateTime.month(.narrow).locale(AppSettings.locale)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 140, alignment: .bottom)
                .padding(.vertical, 6)
            }
            Section(String(localized: "Am häufigsten gekocht", bundle: .module)) {
                ForEach(Array(statistics.mostCooked.prefix(5)), id: \.id) { dish in
                    HStack {
                        Text(dish.name)
                            .lineLimit(2)
                        Spacer()
                        // The count keeps its room; a long name wrapped it to "1" and "×".
                        // (Skip has no layoutPriority.)
                        Text(String(localized: "\(dish.count)×", bundle: .module))
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// "3 Min. langsamer", "2 Min. schneller" or "wie geplant".
    private func againstPlan(_ over: Double) -> String {
        let minutes = Int(abs(over).rounded())
        if over >= 0.5 { return String(localized: "\(minutes) Min. langsamer", bundle: .module) }
        if over <= -0.5 { return String(localized: "\(minutes) Min. schneller", bundle: .module) }
        return String(localized: "wie geplant", bundle: .module)
    }
}

/// Several dishes as one menu: the starter on the table so many minutes
/// before the main, the main cooked while the guests eat (the iPhone's
/// MenuComposerView, KitchenMenu.combined in the package).
struct MenuComposerView: View {
    let library: CookLibrary
    let onSave: (KitchenDish) -> Void
    @State var name = ""
    @State var dishIDs: [String] = ["", ""]
    @State var labels: [String] = ["", ""]
    @State var gaps: [Int] = [20, 0]
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    private var choices: [KitchenDish] { library.ownDishes.filter { $0.source != .menu } + library.samples }

    private func defaultLabel(_ index: Int) -> String {
        switch (dishIDs.count, index) {
        case (2, 0), (3, 0): return String(localized: "Vorspeise", bundle: .module)
        case (2, 1), (3, 1): return String(localized: "Hauptgang", bundle: .module)
        case (3, 2): return String(localized: "Dessert", bundle: .module)
        default: return String(localized: "\(index + 1). Gang", bundle: .module)
        }
    }

    private func label(_ index: Int) -> String {
        let typed = labels[index].trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? defaultLabel(index) : typed
    }

    /// The menu as a dish, once every course has one.
    private var combined: KitchenDish? {
        var courses = [KitchenMenuCourse]()
        for index in dishIDs.indices {
            guard let dish = choices.first(where: { $0.id == dishIDs[index] }) else { return nil }
            courses.append(KitchenMenuCourse(dish: dish.scaled(by: library.portionFactor(for: dish.id)),
                                             label: label(index), gapAfterMinutes: gaps[index]))
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return KitchenMenu.combined(name: title.isEmpty ? String(localized: "Menü", bundle: .module) : title,
                                    courses: courses) { course in
            String(localized: "\(course /*%@*/) servieren", bundle: .module)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name des Menüs", bundle: .module), text: $name)
                } footer: {
                    Text(String(localized: "Die Gänge werden zu einem Plan: Die Vorspeise kommt so viele Minuten vor dem Hauptgang auf den Tisch, wie Du angibst, und der Hauptgang wird gekocht, während die Gäste essen.", bundle: .module))
                }
                ForEach(Array(dishIDs.indices), id: \.self) { index in
                    Section(label(index)) {
                        Picker(String(localized: "Gericht", bundle: .module), selection: $dishIDs[index]) {
                            Text(String(localized: "Bitte wählen", bundle: .module)).tag("")
                            ForEach(choices, id: \.id) { dish in
                                Text(dish.name).tag(dish.id)
                            }
                        }
                        .labelsHidden()
                        TextField(defaultLabel(index), text: $labels[index])
                        if index < dishIDs.count - 1 {
                            Stepper(gaps[index] == 0
                                    ? String(localized: "Zusammen mit dem nächsten Gang", bundle: .module)
                                    : String(localized: "\(gaps[index]) Min. bis zum nächsten Gang", bundle: .module),
                                    value: $gaps[index], in: 0...90, step: 5)
                        }
                        if dishIDs.count > 2 {
                            Button(String(localized: "Entfernen", bundle: .module), role: .destructive) {
                                dishIDs.remove(at: index)
                                labels.remove(at: index)
                                gaps.remove(at: index)
                            }
                        }
                    }
                }
                if dishIDs.count < 5 {
                    Section {
                        Button(String(localized: "Gang hinzufügen", bundle: .module)) {
                            dishIDs.append("")
                            labels.append("")
                            gaps.append(0)
                        }
                    }
                }
                Section(String(localized: "Plan", bundle: .module)) {
                    if let combined {
                        if let plan = DishPlan(dish: combined, budget: library.budget, burners: library.burners, ovens: library.ovens) {
                            Text(plan.verdict)
                                .fontWeight(.semibold)
                                .foregroundStyle(plan.fits ? Palette.good(colorScheme) : Palette.danger(colorScheme))
                            Text(plan.reason)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(String(localized: "\(combined.tasks.count) Schritte, \(combined.ingredients.count) Zutaten, Plan \(plan.schedule.makespan) Min.", bundle: .module))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if let reason = DishPlan.failure(dish: combined, budget: library.budget, burners: library.burners, ovens: library.ovens) {
                            Text(reason)
                                .font(.footnote)
                                .foregroundStyle(Palette.danger(colorScheme))
                        }
                    } else {
                        Text(String(localized: "Wähle für jeden Gang ein Gericht.", bundle: .module))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(String(localized: "Menü zusammenstellen", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Abbrechen", bundle: .module)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Sichern", bundle: .module)) {
                        if let combined {
                            onSave(combined)
                            dismiss()
                        }
                    }
                    .disabled(combined == nil)
                }
            }
        }
        .tint(Palette.accent(colorScheme))
    }
}
