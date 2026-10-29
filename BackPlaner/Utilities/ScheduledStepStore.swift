//
//  ScheduledStepStore.swift
//  BackPlaner
//
//  The scheduled steps of all plans as the planning logic sees them: plain
//  values and the handful of queries planning needs, without saying where
//  they are kept. On iOS that is Core Data (CoreDataScheduledStepStore);
//  tests use a store in memory, and another platform can bring its own.
//

import Foundation

/// One scheduled step of a plan — the same fields as the Core Data entity
/// `NextStep`, as a plain value.
struct ScheduledStepData: Equatable {
    /// `nil` only on steps stored before they had an id.
    var id: UUID?
    /// Groups the steps of one planning run; `nil` on steps planned before
    /// plans had an id.
    var planID: UUID?
    var recipeName: String
    var instruction: String
    var step: Double
    /// Minutes after the plan's start.
    var startTime: Int
    var duration: Int
    var date: Date
    /// Queued by `RecurringBakePlanner` rather than by the user.
    var isAutomaticRecurrence: Bool
    /// The serving scale the plan was made at; `0` on steps planned before
    /// it was recorded.
    var servingScale: Double
}

extension ScheduledStepData {
    /// Whether the step should already be shown; see
    /// `RecurringBakePlanner.isVisible(date:isAutomaticRecurrence:at:)`.
    func isVisible(at now: Date = Date()) -> Bool {
        RecurringBakePlanner.isVisible(date: date, isAutomaticRecurrence: isAutomaticRecurrence, at: now)
    }
}

/// Where the scheduled steps are kept.
protocol ScheduledStepStore {
    /// The scheduled steps of every recipe except `recipeName`.
    func steps(excludingRecipe recipeName: String) -> [ScheduledStepData]
    /// Whether `recipeName` has any scheduled step.
    func hasSteps(recipeName: String) -> Bool
    /// Whether `recipeName` has a scheduled step dated at or after `date`.
    func hasSteps(recipeName: String, onOrAfter date: Date) -> Bool
    /// Adds the steps and saves them.
    func add(_ steps: [ScheduledStepData])
    /// Deletes every scheduled step of `recipeName` and saves.
    func removeSteps(recipeName: String)
}

extension BakePlan {
    /// Every step of the plan, the generated ones included, as the scheduled
    /// steps to store for it. `servingScale` is the factor the plan was made
    /// at, so the plan's ingredient lists show the amounts that are actually
    /// weighed out. `isAutomaticRecurrence` marks steps queued by
    /// `RecurringBakePlanner` rather than by the user.
    func scheduledStepData(planID: UUID, servingScale: Double,
                           isAutomaticRecurrence: Bool = false) -> [ScheduledStepData] {
        allSteps.map { step in
            ScheduledStepData(id: UUID(),
                              planID: planID,
                              recipeName: recipeName,
                              instruction: step.instruction,
                              step: step.step,
                              startTime: step.startTime,
                              duration: step.duration,
                              date: date(of: step),
                              isAutomaticRecurrence: isAutomaticRecurrence,
                              servingScale: servingScale)
        }
    }

    func issues(from store: any ScheduledStepStore) -> [BakePlanIssue] {
        issues(existingWindows: BakePlanValidator.scheduledBakeWindows(excluding: recipeName, from: store))
    }
}

extension BakePlanValidator {
    /// The oven phases of all plans that are currently scheduled, without the
    /// plan of `recipeName` (which is about to be replaced) and without bakes
    /// that are already over.
    static func scheduledBakeWindows(
        excluding recipeName: String,
        from store: any ScheduledStepStore,
        now: Date = Date()
    ) -> [BakeWindow] {
        Dictionary(grouping: store.steps(excludingRecipe: recipeName), by: \.recipeName)
            .compactMap { name, steps in
                bakeWindow(
                    recipeName: name,
                    steps: steps.map {
                        PlannedStep(instruction: $0.instruction, step: $0.step, date: $0.date)
                    }
                )
            }
            .filter { $0.end > now }
    }
}

extension BakePlanAdvisor {
    /// The suggestions for the baking views: the day window from the
    /// settings, nothing before now or beyond the picker's range, and the
    /// bakes already scheduled.
    static func nightFreeDates(for plan: BakePlan, from store: any ScheduledStepStore,
                               now: Date = Date()) -> [NightFreeDate] {
        let (dayStart, dayEnd) = BakePlanValidator.dayWindow()
        let range = GlobalVariables.planningDateRange(around: now)
        guard now < range.upperBound else { return [] }
        return nightFreeDates(
            for: plan, dayStart: dayStart, dayEnd: dayEnd,
            allowedDates: now...range.upperBound,
            existingWindows: BakePlanValidator.scheduledBakeWindows(excluding: plan.recipeName, from: store),
            ovenCount: GlobalVariables.ovenCount
        )
    }
}
