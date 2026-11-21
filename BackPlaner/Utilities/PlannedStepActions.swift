//
//  PlannedStepActions.swift
//  BackPlaner
//
//  What the list and the timeline of planned steps do alike: find the
//  component a step mixes, delete steps together with their reminders, and
//  turn a plan into the Backtag-Zettel or into calendar entries. Kept out
//  of the two views so that both offer the same.
//

import BakePlannerCore
import CoreData
import Foundation
import SwiftUI

enum PlannedStepComponent {

    /// The component a planned step mixes, with its ingredients — or `nil`
    /// for every other step.
    ///
    /// A planned step stores neither its instruction nor its component, only
    /// the recipe name and the step number. A public recipe and the user's
    /// own copy share that name; PlannedStepSource tells which one the step
    /// came from.
    static func column(for nextStep: NextStep, recipes: some Sequence<Recipe>,
                       publicRecipes: [RecipeFB]) -> ComponentColumn? {
        let recipeFB = publicRecipes.first { $0.name == nextStep.recipeName }
        let recipe = recipes.first { $0.name == nextStep.recipeName }
        switch PlannedStepSource.source(
            ofStep: nextStep.step, instruction: nextStep.instruction,
            publicSteps: recipeFB?.instructions.map { PlannedStepSource.Step(step: $0.step, instruction: $0.instruction) },
            ownSteps: recipe?.instructionsArray.map { PlannedStepSource.Step(step: $0.step, instruction: $0.instruction) }
        ) {
        case .publicRecipe:
            return recipeFB.flatMap { ScheduledStepComponent.column(for: $0, step: nextStep.step, instructionText: nextStep.instruction) }
        case .ownRecipe:
            return recipe.flatMap { ScheduledStepComponent.column(for: $0, step: nextStep.step, instructionText: nextStep.instruction) }
        case nil:
            return nil
        }
    }

    /// The component's name and its ingredient lines at the plan's amount —
    /// what the reminders name and the user weighs out — or `nil` for a step
    /// that mixes nothing.
    static func ingredients(for nextStep: NextStep, recipes: some Sequence<Recipe>,
                            publicRecipes: [RecipeFB]) -> (name: String, lines: [String])? {
        guard let column = column(for: nextStep, recipes: recipes, publicRecipes: publicRecipes) else { return nil }
        return (column.name, BakeModeText.ingredientLines(of: column, scale: nextStep.effectiveServingScale))
    }
}

enum PlannedStepDeletion {

    /// Removes `steps` together with their pending reminders. A recipe left
    /// without any plan loses the history entries its plans wrote, unless
    /// someone has written into them. Returns false when the save failed;
    /// the context is rolled back then.
    @discardableResult
    static func delete(_ steps: [NextStep], recipes: some Sequence<Recipe>,
                       in context: NSManagedObjectContext) -> Bool {
        guard !steps.isEmpty else { return false }

        // Reminders are matched by instruction and date, so this has to run
        // while the steps still exist.
        NotificationActions.cancelPendingNotifications(for: steps)

        let recipeNames = Set(steps.map(\.recipeName))
        let planIDs = Set(steps.compactMap(\.planID))
        do {
            for step in steps {
                context.delete(step)
            }
            try context.save()
        } catch {
            context.rollback()
            AppLog.persistence.error("Could not delete next steps")
            return false
        }

        let store = CoreDataScheduledStepStore(context: context)
        for recipe in recipes where recipeNames.contains(recipe.name) && !store.hasSteps(recipeName: recipe.name) {
            BakePlanScheduler.removePlannedBakeEntries(of: recipe, in: context)
        }
        // A plan deleted whole gives its pantry reservations back; a plan
        // that still has steps keeps them.
        let remaining = Set(store.allSteps().compactMap(\.data.planID))
        PantryLedgerService.release(planIDs: planIDs.subtracting(remaining), in: context)
        return true
    }
}

enum PlannedStepExport {

    /// The Backtag-Zettel of `steps`, with the ingredients of each mixing step.
    static func bakeDaySheet(steps: [NextStep],
                             ingredients: (NextStep) -> (name: String, lines: [String])?) -> BakeDaySheet {
        BakeDaySheet(steps: steps.map { ScheduledStepData($0) }, ingredients: { step in
            steps.first(where: { $0.id == step.id }).flatMap(ingredients)
        })
    }

    /// Puts `steps` into the user's default calendar, one event per step,
    /// and returns how many were made — zero when there was nothing to add.
    /// Throws when the calendar may not be written.
    static func addToCalendar(_ steps: [NextStep]) async throws -> Int {
        let entries = PlanCalendarEntry.entries(for: steps.map { ScheduledStepData($0) })
        guard !entries.isEmpty else { return 0 }
        return try await CalendarExport.add(entries)
    }
}

/// Shifting a step while earlier steps of the same plan lie in the past
/// unfinished: the baker is asked whether those count as done, because a
/// plan whose first step is overdue and whose later steps were just moved
/// would otherwise keep nagging about the overdue one.
enum PlannedStepShift {

    /// The steps of `step`'s plan that come before it and are already due
    /// at `now` — overdue and not marked done (a done step is deleted).
    /// Earliest first.
    static func overdueEarlierSteps(of step: NextStep, among steps: some Sequence<NextStep>,
                                    now: Date = Date()) -> [NextStep] {
        steps.filter { other in
            other !== step
                && other.recipeName == step.recipeName
                && other.planID == step.planID
                && other.date < now
                && (other.date < step.date || (other.date == step.date && other.step < step.step))
        }
        .sorted { ($0.date, $0.step) < ($1.date, $1.step) }
    }
}

/// A shift held back until the baker has said what happens to the
/// overdue steps before it. Holds no managed objects: the steps are
/// deleted when the baker confirms, and the dialog is still on screen
/// while SwiftUI re-renders it — reading a deleted step there crashed.
struct PendingStepShift: Identifiable {
    let id: NSManagedObjectID
    let minutes: Int
    let includeFollowing: Bool
    /// The overdue earlier steps, earliest first.
    let overdueIDs: [NSManagedObjectID]
    /// What the dialog says about them, made while they still exist.
    let message: String

    init(id: NSManagedObjectID, minutes: Int, includeFollowing: Bool, overdue: [NextStep]) {
        self.id = id
        self.minutes = minutes
        self.includeFollowing = includeFollowing
        overdueIDs = overdue.map(\.objectID)
        if overdue.count == 1, let step = overdue.first {
            let time = step.date.formatted(.dateTime.hour(.twoDigits(amPM: .abbreviated)).minute())
            message = String(localized: "„\(step.instruction)“ (\(time)) liegt in der Vergangenheit und ist nicht erledigt. Soll der Schritt als erledigt gelten, bevor verschoben wird?")
        } else {
            message = String(localized: "\(overdue.count) Schritte dieses Plans liegen in der Vergangenheit und sind nicht erledigt. Sollen sie als erledigt gelten, bevor verschoben wird?")
        }
    }
}

extension View {
    /// The question for a `PendingStepShift`: mark the overdue steps done
    /// and shift, or leave everything as it is. An alert, not a
    /// confirmation dialog: on the iPhone the dialog came as a popover
    /// without its cancel button.
    func overdueStepsConfirmation(_ pending: Binding<PendingStepShift?>,
                                  onMarkDoneAndShift: @escaping (PendingStepShift) -> Void) -> some View {
        alert("Nicht erledigte Schritte", isPresented: Binding(
            get: { pending.wrappedValue != nil },
            set: { if !$0 { pending.wrappedValue = nil } }
        ), presenting: pending.wrappedValue) { shift in
            Button("Als erledigt markieren und verschieben") {
                pending.wrappedValue = nil
                onMarkDoneAndShift(shift)
            }
            Button("Abbrechen", role: .cancel) { }
        } message: { shift in
            Text(verbatim: shift.message)
        }
    }
}
