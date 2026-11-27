import BakePlannerCore
import SkipKit
import SwiftUI

/// A dish's plan: the verdict with its reason and figures, the components
/// with their hands-on time, and the steps in the order they come.
struct DishPlanView: View {
    let library: CookLibrary
    let dishID: String
    @State var editing = KitchenDish(name: "", tasks: [])
    @State var showsEditor = false
    @State var confirmsDeletion = false
    @State var exportURL: URL?
    @State var showsExporter = false
    @State var cooking = false
    @State var shopping = false
    @State var showsLearned = false
    @State var printing = false
    /// The plan as a list instead of the timeline, kept like the iPhone's
    /// switch (settings.planAsList).
    @State var planAsList = SettingsFile.flag("settings.planAsList", default: false)
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    private var isOwn: Bool { library.ownDishes.contains { $0.id == dishID } }

    var body: some View {
        ZStack {
            WarmBackground().ignoresSafeArea()
            if let dish = library.dish(id: dishID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(dish.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Palette.title(colorScheme))
                        if let plan = library.plan(for: dish) {
                            Button {
                                cooking = true
                            } label: {
                                Label(String(localized: "Kochen starten", bundle: .module), systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            verdictCard(plan)
                            ingredientsCard(plan)
                            if !CookRunLog.shared.runs(of: dishID).isEmpty {
                                runsCard
                            }
                            componentsCard(plan)
                            stepsCard(plan)
                        } else {
                            Text(library.failure(for: dish) ?? "")
                                .foregroundStyle(Palette.danger(colorScheme))
                                .cardStyle()
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(String(localized: "Plan", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(String(localized: "Ablaufplan als PDF", bundle: .module)) {
                        printing = true
                    }
                    if isOwn {
                        Button(String(localized: "Bearbeiten", bundle: .module)) {
                            if let dish = library.dish(id: dishID) {
                                editing = dish
                                showsEditor = true
                            }
                        }
                        Button(String(localized: "Teilen", bundle: .module)) {
                            if let dish = library.dish(id: dishID) {
                                exportURL = library.exportFile(of: [dish])
                                if exportURL != nil { showsExporter = true }
                            }
                        }
                        Button(String(localized: "Gericht löschen", bundle: .module), role: .destructive) {
                            confirmsDeletion = true
                        }
                    } else {
                        Button(String(localized: "Als Vorlage übernehmen", bundle: .module)) {
                            if let dish = library.dish(id: dishID) {
                                editing = library.template(from: dish)
                                showsEditor = true
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel(Text(String(localized: "Mehr", bundle: .module)))
            }
        }
        .appSheet(isPresented: $showsEditor) {
            DishEditorView(library: library, dish: editing) { dish in
                library.save(dish)
            }
        }
        .withDocumentExporter(isPresented: $showsExporter, contentType: .data, documentURL: exportURL)
        .appSheet(isPresented: $printing) {
            if let dish = library.dish(id: dishID), let plan = library.plan(for: dish) {
                PlanPDFSheet(plan: plan)
            }
        }
        .appSheet(isPresented: $showsLearned) {
            if let dish = library.dish(id: dishID) {
                LearnedTimesView(dish: dish,
                                 suggestions: KitchenTimeLearning.suggestions(for: dish, from: CookRunLog.shared.runs(of: dishID))) { learned in
                    library.save(learned)
                }
            }
        }
        .appSheet(isPresented: $shopping) {
            if let dish = library.dish(id: dishID), let plan = library.plan(for: dish) {
                ShoppingListView(dish: plan.dish)
            }
        }
        .appSheet(isPresented: $cooking, backDismissDisabled: true) {
            if let dish = library.dish(id: dishID), let plan = library.plan(for: dish) {
                // A run of this dish still under way is taken up, not started anew.
                if let state = CookRunState.load(), state.dishID == dishID, state.isResumable {
                    CookModeView(plan: plan, restoring: state)
                } else {
                    CookModeView(plan: plan)
                }
            }
        }
        .alert(String(localized: "Gericht löschen?", bundle: .module), isPresented: $confirmsDeletion) {
            Button(String(localized: "Löschen", bundle: .module), role: .destructive) {
                library.delete(id: dishID)
                dismiss()
            }
            Button(String(localized: "Abbrechen", bundle: .module), role: .cancel) {}
        }
    }

    private func verdictCard(_ plan: DishPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.verdict)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(plan.fits ? Palette.good(colorScheme) : Palette.danger(colorScheme))
            Text(plan.reason)
                .font(.subheadline)
                .foregroundStyle(Palette.subtitle(colorScheme))
            HStack(spacing: 14) {
                Text(String(localized: "\(plan.schedule.makespan) Min.", bundle: .module))
                Text(String(localized: "Kette \(plan.schedule.criticalPathMinutes) Min.", bundle: .module))
                Text(String(localized: "Hände \(plan.schedule.handsMinutes) Min.", bundle: .module))
            }
            .font(.caption)
            .foregroundStyle(Palette.subtitle(colorScheme))
        }
        .cardStyle()
    }

    /// How many ingredients, for how many, and the shopping list.
    @ViewBuilder
    private func ingredientsCard(_ plan: DishPlan) -> some View {
        if !plan.dish.ingredients.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "\(plan.dish.ingredients.count) Zutaten", bundle: .module))
                    .font(.headline)
                portionsControl(base: library.dish(id: dishID)?.servings)
                Button(String(localized: "Einkaufsliste", bundle: .module)) {
                    shopping = true
                }
                .buttonStyle(.bordered)
            }
            .cardStyle()
        }
    }

    /// For how many: persons when the recipe says, otherwise a factor.
    /// Only the amounts change; the steps keep their minutes.
    @ViewBuilder
    private func portionsControl(base: Int?) -> some View {
        let factor = library.portionFactor(for: dishID)
        if let base, base > 0 {
            let persons = max(1, Int((Double(base) * factor).rounded()))
            Stepper(String(localized: "Für \(persons) Personen", bundle: .module),
                    value: Binding(get: { persons },
                                   set: { library.setPortionFactor(KitchenPortions.factor(servings: $0, base: base), for: dishID) }),
                    in: 1...24)
            if persons != base {
                Text(String(localized: "Rezept für \(base) Personen · die Zeiten bleiben gleich", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(Palette.subtitle(colorScheme))
            }
        } else {
            let factors = KitchenPortions.factors
            let index = factors.firstIndex(where: { abs($0 - factor) < 0.001 }) ?? 1
            let shown = IngredientDraft.text(for: factors[index])
            Stepper(String(localized: "Menge ×\(shown /*%@*/)", bundle: .module),
                    value: Binding(get: { index }, set: { library.setPortionFactor(factors[$0], for: dishID) }),
                    in: 0...(factors.count - 1))
            if factors[index] != 1 {
                Text(String(localized: "Die Zeiten bleiben gleich", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(Palette.subtitle(colorScheme))
            }
        }
    }

    /// The times this dish was cooked on the stopwatch, newest first.
    private var runsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Gekocht", bundle: .module))
                .font(.headline)
            if let dish = library.dish(id: dishID),
               !KitchenTimeLearning.suggestions(for: dish, from: CookRunLog.shared.runs(of: dishID)).isEmpty {
                Button(String(localized: "Gemessene Zeiten übernehmen", bundle: .module)) {
                    showsLearned = true
                }
                .buttonStyle(.bordered)
            }
            ForEach(Array(CookRunLog.shared.runs(of: dishID).prefix(5)), id: \.id) { run in
                HStack {
                    // In the app's language: Locale.current does not follow the
                    // device on Android.
                    Text(run.startedAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(AppSettings.locale)))
                        .font(.subheadline)
                    Spacer()
                    Text(run.relaxed == true ? String(localized: "Entspannt", bundle: .module)
                                             : KitchenCookRun.clockText(run.totalSeconds))
                        .font(.subheadline)
                        .foregroundStyle(Palette.accentText(colorScheme))
                }
            }
        }
        .cardStyle()
    }

    /// The hands-on minutes of each component, longest first.
    private func componentsCard(_ plan: DishPlan) -> some View {
        let rows = plan.schedule.handsByComponent.map { ComponentHands(component: $0.component, minutes: $0.minutes) }
        let longest = max(1, rows.first?.minutes ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Handarbeit je Komponente", bundle: .module))
                .font(.headline)
            ForEach(rows) { row in
                ComponentHandsRow(row: row, longest: longest)
            }
        }
        .cardStyle()
    }

    /// The plan as a timeline per component, or every step at its minute
    /// in the order of the plan.
    private func stepsCard(_ plan: DishPlan) -> some View {
        let placements = plan.schedule.placements.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Zeitplan", bundle: .module))
                .font(.headline)
            Picker(String(localized: "Darstellung", bundle: .module), selection: $planAsList) {
                Text(String(localized: "Zeitachse", bundle: .module)).tag(false)
                Text(String(localized: "Liste", bundle: .module)).tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: planAsList) { _, asList in
                SettingsFile.set(asList, forKey: "settings.planAsList")
            }
            if !planAsList {
                PlanTimelineView(layout: KitchenTimelineLayout(schedule: plan.schedule, components: plan.dish.components))
            } else {
                stepRows(placements)
            }
        }
        .cardStyle()
    }

    private func stepRows(_ placements: [KitchenPlacement]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(placements, id: \.id) { placement in
                HStack(alignment: .top, spacing: 10) {
                    Text(verbatim: "\(placement.start)–\(placement.end)")
                        .font(.caption)
                        .foregroundStyle(Palette.accentText(colorScheme))
                        .frame(width: 56, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(placement.task.name)
                            .font(.subheadline)
                        Text(stepDetail(placement))
                            .font(.caption)
                            .foregroundStyle(Palette.subtitle(colorScheme))
                    }
                }
            }
        }
    }

    /// "Wirsing · Herd · 3 Min. Hände" – where and how long the hands work.
    private func stepDetail(_ placement: KitchenPlacement) -> String {
        var parts = [placement.task.component]
        switch placement.task.station {
        case .burner: parts.append(String(localized: "Herd", bundle: .module))
        case .oven: parts.append(String(localized: "Ofen", bundle: .module))
        case nil: break
        }
        if placement.task.handsMinutes > 0 {
            parts.append(String(localized: "\(placement.task.handsMinutes) Min. Hände", bundle: .module))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// One component's hands-on minutes, for the bar chart of the plan.
struct ComponentHands: Identifiable {
    let component: String
    let minutes: Int
    var id: String { component }
}

struct ComponentHandsRow: View {
    let row: ComponentHands
    let longest: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.component.isEmpty ? String(localized: "Ohne Komponente", bundle: .module) : row.component)
                Spacer()
                Text(String(localized: "\(row.minutes) Min.", bundle: .module))
                    .foregroundStyle(Palette.subtitle(colorScheme))
            }
            .font(.subheadline)
            GeometryReader { proxy in
                Capsule()
                    .fill(Palette.accent(colorScheme))
                    .frame(width: proxy.size.width * Double(row.minutes) / Double(longest), height: 6)
            }
            .frame(height: 6)
        }
    }
}
