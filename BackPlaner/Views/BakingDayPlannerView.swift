//
//  BakingDayPlannerView.swift
//  BackPlaner
//
//  "Backtag planen" from the recipe list's "Mehr" menu: pick the breads,
//  say when the last one is to be finished and how many ovens there are,
//  and the optimizer (BakingDayOptimizer in the package) lays the start
//  times so that the ovens and the pause between bakes fit. "Alle planen"
//  puts every plan into effect the way "Jetzt planen" does for one.
//

import BakePlannerCore
import CoreData
import SwiftUI

struct BakingDayPlannerView: View {

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>

    @State private var finishBy: Date = BakingDayPlannerView.defaultFinish()
    @State private var ovenCount = AppSettings.storedOvenCount
    @State private var selection: Set<NSManagedObjectID> = []
    @State private var searchText = ""
    @State private var schedule: BakingDaySchedule?
    /// The breads that had a plan when the day was worked out; noted then,
    /// not read live, or the rows would flip while "Alle planen" runs.
    @State private var alreadyPlanned: Set<String> = []
    @State private var plannedCount: Int?

    private let timeText = TimeCalculation()
    private let dateText = DateFormat()

    /// Tomorrow at noon: a baking day usually ends with lunch.
    private static func defaultFinish(now: Date = Date()) -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// Starters are fed, not baked; they have no place on a baking day.
    private var breads: [Recipe] {
        recipes.filter { !StarterRecipe.isStarterFeeding($0) && !$0.instructionsArray.isEmpty }
    }

    private var shownBreads: [Recipe] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return breads }
        return breads.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var selectedRecipes: [Recipe] {
        breads.filter { selection.contains($0.objectID) }
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Fertig bis", selection: $finishBy, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .accessibilityIdentifier("bakingDay.finish")
                Stepper(value: $ovenCount, in: 1...6) {
                    Text("Backöfen: \(ovenCount)")
                }
                .accessibilityIdentifier("bakingDay.ovens")
            } footer: {
                Text("Das Brot mit dem längsten Backen ist zur Wunschzeit fertig, die anderen davor. Backpause \(AppSettings.storedBakePause) Minuten, Tagesbeginn und Tagesende aus den Einstellungen.")
            }

            Section {
                TextField("Rezept suchen", text: $searchText)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .accessibilityIdentifier("bakingDay.search")
                ForEach(shownBreads, id: \.objectID) { recipe in
                    Button {
                        if selection.contains(recipe.objectID) {
                            selection.remove(recipe.objectID)
                        } else {
                            selection.insert(recipe.objectID)
                        }
                        schedule = nil
                    } label: {
                        HStack {
                            Image(systemName: selection.contains(recipe.objectID) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selection.contains(recipe.objectID) ? Theme.accentText : Theme.subtitle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.name)
                                    .font(Theme.bodyFont(15))
                                    .foregroundColor(Theme.cardTitle)
                                Text(Rational.displayHoursMinutes(RecurringBakePlanner.planDuration(of: recipe)))
                                    .font(Theme.bodyFont(12))
                                    .foregroundColor(Theme.subtitle)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection.contains(recipe.objectID) ? [.isButton, .isSelected] : [.isButton])
                    .accessibilityIdentifier("bakingDay.recipe")
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
                Button {
                    compute()
                } label: {
                    Label("Backtag berechnen", systemImage: "wand.and.stars")
                }
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("bakingDay.compute")
            }

            if let schedule {
                Section("Backtag") {
                    ForEach(schedule.placements) { placement in
                        placementRow(placement)
                    }
                    if !schedule.unplaced.isEmpty {
                        Label {
                            Text("Ohne Zeitangaben: \(schedule.unplaced.map(\.recipe.name).joined(separator: ", "))")
                        } icon: {
                            Image(systemName: "exclamationmark.circle")
                        }
                        .font(Theme.bodyFont(13))
                        .foregroundColor(Theme.warning)
                    }
                }
                Section {
                    Button {
                        planAll(schedule)
                    } label: {
                        Label("Alle planen", systemImage: "calendar.badge.plus")
                    }
                    .disabled(schedule.placements.isEmpty || schedule.placements.contains { $0.startsInThePast(now: Date()) })
                    .accessibilityIdentifier("bakingDay.planAll")
                } footer: {
                    Text("Legt für jedes Brot die Schritte und Erinnerungen an, wie „Jetzt planen“ auf der Rezeptseite. Ein Brot, das schon einen Plan hat, bekommt den neuen an dessen Stelle.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .warmBackground()
        .navigationTitle("Backtag planen")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: finishBy) { _, _ in schedule = nil }
        .onChange(of: ovenCount) { _, _ in schedule = nil }
        .alert("Backtag geplant", isPresented: Binding(
            get: { plannedCount != nil },
            set: { if !$0 { plannedCount = nil } }
        )) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text("\(plannedCount ?? 0) Brote geplant. Die Schritte stehen unter „Nächste Schritte“, die Erinnerungen sind gesetzt.")
        }
    }

    /// One bread of the baking day: when it starts and finishes, its oven
    /// phase, and what to watch.
    @ViewBuilder private func placementRow(_ placement: BakingDayPlacement) -> some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 3) {
            Text(placement.recipeName)
                .font(Theme.brandFont(15))
                .foregroundColor(Theme.cardTitle)
            Text("Start \(dateText.calculateDate(dT: placement.start)), \(timeText.calculateTime(t: placement.start)) · Fertig \(timeText.calculateTime(t: placement.finish))")
                .font(Theme.bodyFont(13))
                .foregroundColor(Theme.subtitle)
            if let window = placement.bakeWindow {
                Label {
                    Text("Ofen \(timeText.calculateTime(t: window.start)) bis \(timeText.calculateTime(t: window.end))")
                } icon: {
                    Image(systemName: "oven")
                }
                .font(Theme.bodyFont(13))
                .foregroundColor(Theme.subtitle)
            }
            if placement.hasNightSteps {
                Label("Schritte in der Nacht", systemImage: "moon.zzz")
                    .font(Theme.bodyFont(12))
                    .foregroundColor(Theme.warning)
            }
            if placement.conflictsWithOvens {
                Label("Kein Ofen frei – überschneidet sich mit einem anderen Backen", systemImage: "exclamationmark.triangle")
                    .font(Theme.bodyFont(12))
                    .foregroundColor(Theme.danger)
            }
            if placement.startsInThePast(now: now) {
                Label("Müsste schon laufen – Wunschzeit später wählen", systemImage: "clock.badge.exclamationmark")
                    .font(Theme.bodyFont(12))
                    .foregroundColor(Theme.danger)
            }
            if alreadyPlanned.contains(placement.recipeName) {
                Label("Hat schon einen Plan – wird ersetzt", systemImage: "arrow.triangle.2.circlepath")
                    .font(Theme.bodyFont(12))
                    .foregroundColor(Theme.subtitle)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bakingDay.placement")
    }

    private func compute() {
        let chosen = selectedRecipes
        let names = Set(chosen.map(\.name))
        // The plans of the chosen breads are replaced, so their bakes do not
        // block the ovens; everything else scheduled does.
        let existing = BakePlanValidator.scheduledBakeWindows(excluding: "", in: viewContext)
            .filter { !names.contains($0.recipeName) }
        let candidates = chosen.map {
            BakingDayCandidate(id: $0.objectID.uriRepresentation().absoluteString,
                               recipe: RecipeExportData(recipe: $0, includingImage: false))
        }
        let (dayStart, dayEnd) = BakePlanValidator.dayWindow()
        alreadyPlanned = Set(chosen.map(\.name).filter { BakePlanScheduler.hasPendingPlan(recipeName: $0, in: viewContext) })
        schedule = BakingDayOptimizer.schedule(candidates, finishBy: finishBy, now: Date(),
                                               ovenCount: ovenCount, bakePause: AppSettings.storedBakePause,
                                               dayStart: dayStart, dayEnd: dayEnd, existingWindows: existing,
                                               languageCode: AppSettings.locale.identifier)
    }

    /// Every placement becomes a plan: the recipe's earlier plan goes, the
    /// new one is put into effect at the serving size of the settings.
    private func planAll(_ schedule: BakingDaySchedule) {
        let manager = LocalNotificationManager()
        var count = 0
        for placement in schedule.placements {
            guard let recipe = selectedRecipes.first(where: { $0.objectID.uriRepresentation().absoluteString == placement.id }) else { continue }
            let planID = UUID()
            if BakePlanScheduler.hasPlan(recipeName: recipe.name, in: viewContext) {
                BakePlanScheduler.removePlans(recipeName: recipe.name, reminderPrefix: recipe.reminderId,
                                              keeping: planID, in: viewContext)
                BakePlanScheduler.removePlannedBakeEntries(of: recipe, in: viewContext)
            }
            let scale = ServingScale.factor(servingSize: AppSettings.storedServingSize, targetWeight: nil,
                                            baseWeight: recipe.totalWeight)
            BakePlanScheduler.putIntoEffect(placement.plan, for: recipe, planID: planID,
                                            servingScale: scale, manager: manager, in: viewContext)
            count += 1
        }
        plannedCount = count
    }
}
