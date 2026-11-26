//
//  DishPlanView.swift
//  CookPlanner
//
//  One dish planned against the clock: the verdict and its reason, where
//  the hands' minutes go, the timeline, what wants keeping warm, and the
//  way into the cook mode.
//

import BakePlannerCore
import SwiftUI

struct DishPlanView: View {

    @Environment(DishLibrary.self) private var library
    @AppStorage(CookSettings.budgetKey) private var budget = CookSettings.defaultBudget
    @AppStorage(CookSettings.burnersKey) private var burners = CookSettings.defaultBurners
    @AppStorage(CookSettings.ovensKey) private var ovens = CookSettings.defaultOvens
    @State private var dish: KitchenDish
    @State private var cooking = false
    @State private var editing = false
    @State private var shopping = false
    @State private var printing = false
    @State private var shownRun: KitchenCookRun?
    /// The newest record when cooking began, to open the one it adds.
    @State private var runBeforeCooking: String?
    @State private var showingLearned = false
    @State private var savedCopyName: String?
    @State private var runLog = CookRunLog.shared
    /// The plan as a timeline or as a list, remembered.
    @AppStorage("settings.planAsList") private var planAsList = false
    /// How much more or less than the recipe is cooked, kept per dish.
    @State private var portionFactor: Double

    /// Siri's "Kochen starten" and the link behind it: the cook mode comes
    /// up on its own.
    @State private var requests = AppRequests.shared

    init(dish: KitchenDish) {
        _dish = State(initialValue: dish)
        _portionFactor = State(initialValue: CookSettings.portionFactor(for: dish.id))
    }

    /// The dish with its amounts for the chosen portions; the plan, the
    /// cook mode and the shopping list work with this one.
    private var cookedDish: KitchenDish { dish.scaled(by: portionFactor) }

    /// The examples are not the cook's to change; a copy of one is.
    private var isOwn: Bool { dish.source != .sample }

    private var plan: DishPlan? {
        DishPlan(dish: cookedDish, budget: budget, burners: burners, ovens: ovens)
    }

    /// The dish cut within its steps' windows, when the nominal plan does
    /// not fit and cutting is what helps.
    private func fit(for plan: DishPlan) -> KitchenFit? {
        guard !plan.fits, plan.schedule.limit != .hands,
              let fit = try? KitchenScheduler.fit(dish.tasks, kitchen: plan.schedule.kitchen, budget: budget),
              !fit.shortenings.isEmpty else { return nil }
        return fit
    }

    var body: some View {
        ScrollView {
            if plan == nil {
                ContentUnavailableView {
                    Label("Kein Plan", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(DishPlan.failure(dish: cookedDish, budget: budget, burners: burners, ovens: ovens) ?? "Der Plan geht nicht auf.")
                } actions: {
                    if isOwn {
                        Button("Bearbeiten") { editing = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accentBottom)
                    }
                }
                .padding(.top, 40)
            }
            if let plan {
                VStack(alignment: .leading, spacing: 16) {
                    // The name is too long for the bar; it heads the content.
                    Text(verbatim: dish.name)
                        .font(Theme.brandFont(20))
                        .foregroundColor(Theme.title)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    verdictCard(plan)
                    if !dish.ingredients.isEmpty {
                        ingredientsCard
                    }
                    if let fit = fit(for: plan) {
                        fitCard(fit, plan: plan)
                    }
                    handsCard(plan)
                    timelineCard(plan)
                    if !runLog.runs(of: dish.id).isEmpty {
                        runsCard
                    }
                    if !plan.schedule.waits(atLeast: 10).isEmpty {
                        keepWarmCard(plan)
                    }
                    Button {
                        cooking = true
                    } label: {
                        Label("Kochen starten", systemImage: "timer")
                            .font(Theme.bodyFont(17).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentBottom)
                }
                .padding()
            }
        }
        .warmBackground()
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !dish.ingredients.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        shopping = true
                    } label: {
                        Image(systemName: "basket")
                    }
                    .accessibilityLabel("Einkaufsliste")
                }
                if plan != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            printing = true
                        } label: {
                            Image(systemName: "printer")
                        }
                        .accessibilityLabel("Ablaufplan als PDF")
                    }
                }
            }
            if isOwn {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: DishFileExport(dishes: [dish]),
                              preview: SharePreview(Text(verbatim: dish.name))) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Gericht teilen")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bearbeiten") { editing = true }
                }
            }
        }
        .sheet(isPresented: $shopping) {
            ShoppingListView(dish: cookedDish)
        }
        .sheet(isPresented: $printing) {
            if let plan {
                PlanPDFSheet(plan: plan)
            }
        }
        .sheet(item: $shownRun) { run in
            CookRunView(runID: run.id)
        }
        .sheet(isPresented: $showingLearned) {
            LearnedTimesView(dish: dish, suggestions: learnedSuggestions) { learned in
                if learned.id == dish.id {
                    if library.save(learned) { dish = learned }
                } else if library.save(learned) {
                    savedCopyName = learned.name
                }
            }
        }
        .alert("Als eigenes Gericht gesichert", isPresented: Binding(get: { savedCopyName != nil },
                                                                       set: { if !$0 { savedCopyName = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Die Kopie mit den gemessenen Zeiten steht unter „Meine Gerichte“.")
        }
        .sheet(isPresented: $editing) {
            DishEditorView(dish: dish) { saved in
                if library.save(saved) { dish = saved }
            }
        }
        .onChange(of: cooking) { _, isCooking in
            if isCooking { runBeforeCooking = runLog.runs(of: dish.id).first?.id }
        }
        // A cover presented while the push is still animating is dropped;
        // the cook mode comes up once the plan has settled.
        .onChange(of: requests.cookDishID, initial: true) { _, id in
            guard id == dish.id, plan != nil else { return }
            requests.cookDishID = nil
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                if !cooking { cooking = true }
            }
        }
        // A record kept at the end opens at once, for the stars and a photo.
        .fullScreenCover(isPresented: $cooking, onDismiss: {
            if let newest = runLog.runs(of: dish.id).first, newest.id != runBeforeCooking {
                shownRun = newest
            }
        }) {
            if let plan {
                CookModeView(plan: plan)
            }
        }
    }

    private var learnedSuggestions: [KitchenTimeLearning.Suggestion] {
        KitchenTimeLearning.suggestions(for: dish, from: runLog.runs(of: dish.id))
    }

    /// The times this dish was cooked on the stopwatch, newest first.
    private var runsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Gekocht", systemImage: "stopwatch")
                .font(Theme.bodyFont(16).weight(.semibold))
                .foregroundColor(Theme.cardTitle)
            // What the records say the steps really take.
            if !learnedSuggestions.isEmpty {
                Button {
                    showingLearned = true
                } label: {
                    Label("Gemessene Zeiten für \(learnedSuggestions.count) Schritte übernehmen", systemImage: "wand.and.stars")
                        .font(Theme.bodyFont(14).weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.accentText)
            }
            ForEach(runLog.runs(of: dish.id).prefix(5)) { run in
                Button {
                    shownRun = run
                } label: {
                    HStack {
                        RunThumbnail(run: run, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: run.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(Theme.cardTitle)
                            if let rating = run.rating {
                                StarsText(rating: rating)
                            }
                        }
                        Spacer()
                        if !run.isManualEntry {
                            Text(verbatim: KitchenCookRun.clockText(run.totalSeconds))
                                .monospacedDigit()
                                .foregroundColor(Theme.accentText)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundColor(Theme.subtitle)
                    }
                    .font(Theme.bodyFont(14))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Protokoll löschen", role: .destructive) { runLog.delete(id: run.id) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// How much to buy, and the way to the list.
    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(dish.ingredients.count) Zutaten")
                    .font(Theme.bodyFont(16).weight(.semibold))
                    .foregroundColor(Theme.cardTitle)
                Text(verbatim: KitchenShoppingList.groups(of: dish).map(\.component).filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            portionsControl
            Button {
                shopping = true
            } label: {
                Label("Einkaufsliste", systemImage: "basket")
            }
            .buttonStyle(.bordered)
            .tint(Theme.accentText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// For how many: persons when the recipe says, otherwise a factor.
    /// Only the amounts change; the steps keep their minutes.
    @ViewBuilder
    private var portionsControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let base = dish.servings, base > 0 {
                let persons = max(1, Int((Double(base) * portionFactor).rounded()))
                Stepper(value: Binding(get: { persons },
                                       set: { setPortionFactor(KitchenPortions.factor(servings: $0, base: base)) }),
                        in: 1...24) {
                    Text("Für \(persons) Personen")
                        .font(Theme.bodyFont(15))
                        .foregroundColor(Theme.cardTitle)
                }
                if persons != base {
                    Text("Rezept für \(base) Personen · die Zeiten bleiben gleich")
                        .font(Theme.bodyFont(12))
                        .foregroundColor(Theme.subtitle)
                }
            } else {
                let factors = KitchenPortions.factors
                let index = factors.firstIndex(where: { abs($0 - portionFactor) < 0.001 }) ?? 1
                Stepper(value: Binding(get: { index }, set: { setPortionFactor(factors[$0]) }),
                        in: 0...(factors.count - 1)) {
                    Text("Menge ×\(factors[index].formatted(.number.precision(.fractionLength(0...1))))")
                        .font(Theme.bodyFont(15))
                        .foregroundColor(Theme.cardTitle)
                }
                if factors[index] != 1 {
                    Text("Die Zeiten bleiben gleich")
                        .font(Theme.bodyFont(12))
                        .foregroundColor(Theme.subtitle)
                }
            }
        }
    }

    private func setPortionFactor(_ factor: Double) {
        portionFactor = factor
        CookSettings.setPortionFactor(factor, for: dish.id)
    }

    private func verdictCard(_ plan: DishPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.verdict)
                .font(Theme.brandFont(26))
                .foregroundColor(plan.fits ? Theme.good : Theme.danger)
            Text(plan.reason)
                .font(Theme.bodyFont(15))
                .foregroundColor(Theme.subtitle)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Label("\(plan.schedule.makespan) Min.", systemImage: "clock")
                Label("Kette \(plan.schedule.criticalPathMinutes) Min.", systemImage: "link")
                Label("Hände \(plan.schedule.handsMinutes) Min.", systemImage: "hand.raised")
            }
            .font(Theme.bodyFont(13))
            .foregroundColor(Theme.subtitle)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func fitCard(_ fit: KitchenFit, plan: DishPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("So passt es")
                .font(Theme.bodyFont(16).weight(.semibold))
                .foregroundColor(Theme.cardTitle)
            ForEach(fit.shortenings, id: \.task) { cut in
                if let task = plan.dish.tasks.first(where: { $0.id == cut.task }) {
                    Text("\(task.name): \(cut.to) statt \(cut.from) Minuten")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.cardTitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if fit.schedule.fits {
                Text("Mit diesen Garzeiten passt es in \(budget) Minuten")
                    .font(Theme.bodyFont(14))
                    .foregroundColor(Theme.good)
            } else {
                Text("Auch mit den kürzesten Garzeiten fehlen \(fit.schedule.shortfall) Minuten")
                    .font(Theme.bodyFont(14))
                    .foregroundColor(Theme.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func handsCard(_ plan: DishPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Handarbeit je Komponente")
                .font(Theme.bodyFont(16).weight(.semibold))
                .foregroundColor(Theme.cardTitle)
            let total = max(1, plan.schedule.handsMinutes)
            ForEach(plan.schedule.handsByComponent, id: \.component) { entry in
                HStack {
                    Text(verbatim: entry.component)
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.cardTitle)
                    Spacer()
                    Text("\(entry.minutes) Min.")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.subtitle)
                }
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.accent)
                        .frame(width: geometry.size.width * CGFloat(entry.minutes) / CGFloat(total))
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func timelineCard(_ plan: DishPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Zeitplan")
                    .font(Theme.bodyFont(16).weight(.semibold))
                    .foregroundColor(Theme.cardTitle)
                Spacer()
                Picker("Darstellung", selection: $planAsList) {
                    Image(systemName: "chart.bar.xaxis").accessibilityLabel("Zeitachse").tag(false)
                    Image(systemName: "list.bullet").accessibilityLabel("Liste").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
            if planAsList {
                ForEach(plan.schedule.placements.sorted { ($0.start, $0.task.id) < ($1.start, $1.task.id) }) { placement in
                    TimelineRow(placement: placement)
                }
            } else {
                PlanTimelineView(layout: KitchenTimelineLayout(schedule: plan.schedule, components: plan.dish.components))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func keepWarmCard(_ plan: DishPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Warm halten")
                .font(Theme.bodyFont(16).weight(.semibold))
                .foregroundColor(Theme.cardTitle)
            ForEach(plan.schedule.waits(atLeast: 10), id: \.task) { wait in
                if let task = plan.dish.tasks.first(where: { $0.id == wait.task }) {
                    Text("\(task.name) wartet \(wait.minutes) Minuten")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// One step on the timeline: minutes, hands, station, name and component.
struct TimelineRow: View {
    let placement: KitchenPlacement

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(placement.start)–\(placement.end)")
                .font(Theme.bodyFont(13).monospacedDigit())
                .foregroundColor(Theme.subtitle)
                .frame(width: 52, alignment: .trailing)
            HStack(spacing: 4) {
                if placement.task.handsMinutes > 0 {
                    Image(systemName: "hand.raised.fill")
                        .accessibilityLabel("Hände")
                }
                if let symbol = placement.task.stationSymbol {
                    Image(systemName: symbol)
                        .accessibilityLabel(placement.task.station == .oven ? "Ofen" : "Platte")
                }
            }
            .font(.system(size: 12))
            .foregroundColor(Theme.accentText)
            .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: placement.task.name)
                    .font(Theme.bodyFont(14))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if !placement.task.component.isEmpty {
                        Text(verbatim: placement.task.component)
                    }
                    if let window = placement.task.unattendedWindow {
                        Text("\(window.lowerBound)–\(window.upperBound) Min.")
                    }
                    if let temperature = placement.task.ovenTemperature {
                        Text("Ofen \(temperature) °C")
                    }
                }
                .font(Theme.bodyFont(12))
                .foregroundColor(Theme.subtitle)
            }
        }
    }
}
