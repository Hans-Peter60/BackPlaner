import BakePlannerCore
import SwiftUI

/// "Backtag planen" from the recipe list's "Mehr" menu: pick the breads,
/// say when the last one is to be finished and how many ovens there are,
/// and the optimizer (BakingDayOptimizer in the package) lays the start
/// times so that the ovens and the pause between bakes fit. "Alle planen"
/// puts every plan into effect the way "Planen" does for one.
struct BakingDayPlannerView: View {
    let model: AppModel
    @State var finishBy = BakingDayPlannerView.defaultFinish()
    @State var ovenCount = AppSettings.storedOvenCount
    /// The chosen recipes, by their store key.
    @State var selection: Set<String> = []
    @State var searchText = ""
    @State var schedule: BakingDaySchedule?
    /// What the chosen breads need beyond the available pantry.
    @State var shortfalls: [PantryNeed] = []
    /// The breads that had a plan when the day was worked out; noted then,
    /// not read live, or the rows would flip while "Alle planen" runs.
    @State var alreadyPlanned: Set<String> = []
    @State var plannedCount = 0
    @State var showsPlanned = false
    @State var isPlanning = false
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    /// Tomorrow at noon: a baking day usually ends with lunch.
    static func defaultFinish(now: Date = Date()) -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// Starters are fed, not baked; they have no place on a baking day.
    private var breads: [StoredRecipe] {
        model.recipes.filter { !StarterRecipe.isStarterFeeding($0.content) && !$0.content.instructions.isEmpty }
    }

    private var shownBreads: [StoredRecipe] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return breads }
        return breads.filter { $0.content.name.localizedCaseInsensitiveContains(search) }
    }

    private var selectedRecipes: [StoredRecipe] {
        breads.filter { selection.contains($0.id) }
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Fertig bis", selection: $finishBy, displayedComponents: [.date, .hourAndMinute])
                Stepper(value: $ovenCount, in: 1...AppSettings.maximumOvenCount) {
                    Text("Backöfen: \(ovenCount)")
                }
            } footer: {
                Text("Das Brot mit dem längsten Backen ist zur Wunschzeit fertig, die anderen davor – so, dass die Öfen reichen, die Backpause von \(AppSettings.storedBakePause) Minuten gewahrt bleibt und nie zwei Teige zugleich geknetet oder geformt werden.")
            }

            Section {
                TextField("Rezept suchen", text: $searchText)
                ForEach(shownBreads, id: \.id) { recipe in
                    Button {
                        if selection.contains(recipe.id) {
                            selection.remove(recipe.id)
                        } else {
                            selection.insert(recipe.id)
                        }
                        schedule = nil
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: recipe.content.name)
                                    .font(AppFont.body)
                                    .foregroundStyle(Color.primary)
                                Text(verbatim: Rational.displayHoursMinutes(RecurringBakePlanner.planDuration(of: recipe.content)))
                                    .font(AppFont.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selection.contains(recipe.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Palette.accent(colorScheme))
                            }
                        }
                    }
                }
            } header: {
                if selection.isEmpty {
                    Text("Rezepte")
                } else {
                    Text("Rezepte – \(selection.count) ausgewählt")
                }
            } footer: {
                if selection.isEmpty {
                    Text("Wähle mindestens ein Rezept.")
                }
            }

            Section {
                Button("Backtag berechnen") {
                    compute()
                }
                .disabled(selection.isEmpty)
            }

            if let schedule {
                if !shortfalls.isEmpty {
                    Section {
                        ForEach(shortfalls, id: \.name) { need in
                            let amount = PantryMatcher.baseText(need.missingBase, counted: need.isCounted, locale: AppSettings.locale)
                            Text("Es fehlen \(amount) \(need.name)")
                                .font(AppFont.subheadline)
                                .foregroundStyle(Palette.warning(colorScheme))
                        }
                    } header: {
                        Text("Vorrat reicht nicht für alle Brote")
                    } footer: {
                        Text("Gerechnet über alle gewählten Brote gegen den verfügbaren Vorrat, Reservierungen anderer Pläne schon abgezogen. Planen geht trotzdem – die Einkaufsliste eines Rezepts mit „Vorrat abziehen“ holt das Fehlende.")
                    }
                }
                Section {
                    // Keys of their own: the list already uses the recipe
                    // keys for the rows above, and Compose refuses a key twice.
                    ForEach(schedule.placements.map(KeyedPlacement.init), id: \.id) { keyed in
                        placementRow(keyed.placement)
                    }
                    if !schedule.unplaced.isEmpty {
                        Text("Ohne Zeitangaben: \(schedule.unplaced.map(\.recipe.name).joined(separator: ", "))")
                            .font(AppFont.subheadline)
                            .foregroundStyle(Palette.warning(colorScheme))
                    }
                } header: {
                    Text("Backtag")
                }
                Section {
                    Button("Alle planen") {
                        planAll(schedule)
                    }
                    .disabled(isPlanning || schedule.placements.isEmpty
                              || schedule.placements.contains { $0.startsInThePast(now: Date()) })
                } footer: {
                    Text("Legt für jedes Brot die Schritte und Erinnerungen an, wie „Planen“ auf der Rezeptseite. Ein Brot, das schon einen Plan hat, bekommt den neuen an dessen Stelle.")
                }
            }
        }
        .navigationTitle("Backtag planen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fertig") {
                    dismiss()
                }
            }
        }
        .onChange(of: finishBy) { _, _ in schedule = nil }
        .onChange(of: ovenCount) { _, _ in schedule = nil }
        .alert("Backtag geplant", isPresented: $showsPlanned) {
            Button {
                dismiss()
            } label: {
                Text(verbatim: "OK")
            }
        } message: {
            // The singular as its own text: the Android catalog carries no
            // plural rules.
            if plannedCount == 1 {
                Text("Ein Brot geplant. Die Schritte stehen unter „Nächste Schritte“, die Erinnerungen sind gesetzt.")
            } else {
                Text("\(plannedCount) Brote geplant. Die Schritte stehen unter „Nächste Schritte“, die Erinnerungen sind gesetzt.")
            }
        }
    }

    /// A placement under a key that no recipe row carries.
    private struct KeyedPlacement: Identifiable {
        let placement: BakingDayPlacement
        var id: String { "placement:" + placement.id }
        init(_ placement: BakingDayPlacement) { self.placement = placement }
    }

    /// One bread of the baking day: when it starts and finishes, its oven
    /// phase, and what to watch.
    @ViewBuilder private func placementRow(_ placement: BakingDayPlacement) -> some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: placement.recipeName)
                .font(AppFont.headline)
            // The finish carries its date when it is not the chosen day.
            if Calendar.current.isDate(placement.finish, inSameDayAs: finishBy) {
                Text("Start \(PlanText.day(placement.start)), \(PlanText.time(placement.start)) · Fertig \(PlanText.time(placement.finish))")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Start \(PlanText.day(placement.start)), \(PlanText.time(placement.start)) · Fertig \(PlanText.day(placement.finish)), \(PlanText.time(placement.finish))")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let window = placement.bakeWindow {
                Text("Ofen \(PlanText.time(window.start)) bis \(PlanText.time(window.end))")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.secondary)
            }
            if placement.hasNightSteps {
                Text("Schritte in der Nacht")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.warning(colorScheme))
            }
            if placement.overlapsWork {
                Text("Handarbeit fällt mit einem anderen Brot zusammen")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.warning(colorScheme))
            }
            if placement.conflictsWithOvens {
                Text("Kein Ofen frei – überschneidet sich mit einem anderen Backen")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.danger(colorScheme))
            }
            if placement.startsInThePast(now: now) {
                Text("Müsste schon laufen – Wunschzeit später wählen")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.danger(colorScheme))
            }
            if alreadyPlanned.contains(placement.recipeName) {
                Text("Hat schon einen Plan – wird ersetzt")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func compute() {
        let chosen = selectedRecipes
        let names = Set(chosen.map(\.content.name))
        let now = Date()
        let candidates = chosen.map { BakingDayCandidate(id: $0.id, recipe: $0.content) }
        let (dayStart, dayEnd) = BakePlanValidator.dayWindow()
        alreadyPlanned = names.filter { model.hasPlan(recipeName: $0) }
        shortfalls = model.pantryShortfalls(for: chosen, excludingPlansOf: names)
        schedule = BakingDayOptimizer.schedule(candidates, finishBy: finishBy, now: now,
                                               ovenCount: ovenCount, bakePause: AppSettings.storedBakePause,
                                               dayStart: dayStart, dayEnd: dayEnd,
                                               existingWindows: model.scheduledBakeWindows(excludingRecipes: names, now: now),
                                               existingWork: model.scheduledWork(excludingRecipes: names, now: now),
                                               languageCode: AppSettings.locale.identifier)
    }

    /// Every placement becomes a plan: the recipe's earlier plan goes, the
    /// new one is put into effect at the serving size of the settings.
    private func planAll(_ schedule: BakingDaySchedule) {
        isPlanning = true
        let recipes = selectedRecipes
        Task {
            var count = 0
            for placement in schedule.placements {
                guard let recipe = recipes.first(where: { $0.id == placement.id }) else { continue }
                let scale = ServingScale.factor(servingSize: AppSettings.storedServingSize, targetWeight: nil,
                                                baseWeight: recipe.content.totalWeight)
                let outcome = await model.putIntoEffect(placement.plan, recipeID: recipe.id, servingScale: scale,
                                                        replacing: model.hasPlan(recipeName: recipe.content.name))
                if outcome != .failed {
                    count += 1
                }
            }
            plannedCount = count
            isPlanning = false
            showsPlanned = true
        }
    }
}
