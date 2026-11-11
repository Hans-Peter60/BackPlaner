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
