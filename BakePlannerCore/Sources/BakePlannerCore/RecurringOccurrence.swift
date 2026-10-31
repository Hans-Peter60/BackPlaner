//
//  RecurringOccurrence.swift
//  BakePlannerCore
//
//  Which recipe on a rhythm is due now, and with which plan — the choice
//  the iPhone's automatic pass (RecurringBakePlanner.scheduleDueOccurrences
//  in BakePlanScheduler.swift) makes on Core Data, as plain logic Android
//  runs on its own stores.
//

import Foundation

extension RecurringBakePlanner {

    /// A recipe as the automatic pass looks at it.
    public struct RhythmRecipe {
        public var content: RecipeExportData
        /// The finish of its last bake-history entry, if any.
        public var lastBakeFinish: Date?
        /// The start of its last feeding, for a starter; ignored otherwise.
        public var lastFeedingStart: Date?

        public init(content: RecipeExportData, lastBakeFinish: Date?, lastFeedingStart: Date?) {
            self.content = content
            self.lastBakeFinish = lastBakeFinish
            self.lastFeedingStart = lastFeedingStart
        }
    }

    /// The plan of `recipe`'s next occurrence when it is due now, else nil:
    /// a rhythm, steps, something to measure the rhythm from (`rhythmFinish`),
    /// no plan of the recipe still pending, and no clash with another plan's
    /// oven time (which the next pass tries again). Planned from its start,
    /// so the first step keeps its time of day.
    ///
    /// Called recipe by recipe, with each occurrence put into effect before
    /// the next recipe is looked at, so two recipes due at once do not take
    /// the same oven.
    public static func dueOccurrence(of recipe: RhythmRecipe, steps store: ScheduledStepStore, now: Date = Date(),
                                     languageCode: String = AppSettings.locale.identifier,
                                     calendar: Calendar = .current) -> BakePlan? {
        let content = recipe.content
        guard content.recurrenceIntervalDays > 0, !content.instructions.isEmpty else { return nil }

        let isStarter = StarterRecipe.isStarterFeeding(content)
        let duration = planDuration(of: content)
        guard let lastFinish = rhythmFinish(lastBakeFinish: recipe.lastBakeFinish,
                                            lastFeedingStart: isStarter ? recipe.lastFeedingStart : nil,
                                            duration: duration, calendar: calendar),
              !store.hasSteps(recipeName: content.name, onOrAfter: now),
              let start = nextStartDate(lastFinish: lastFinish, duration: duration,
                                        intervalDays: content.recurrenceIntervalDays, now: now, calendar: calendar)
        else { return nil }

        let plan = BakePlan(recipeName: content.name,
                            steps: content.instructions.map {
                                PlanStep(instruction: $0.instruction, step: $0.step, startTime: $0.startTime,
                                         duration: $0.duration)
                            },
                            prepTime: content.prepTime,
                            anchor: .startsAt,
                            date: start,
                            languageCode: languageCode,
                            calendar: calendar,
                            isStarterFeeding: isStarter)
        guard !plan.issues(from: store).contains(where: { $0.severity == .error }) else { return nil }
        return plan
    }
}
