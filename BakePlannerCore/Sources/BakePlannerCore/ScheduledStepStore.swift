//
//  ScheduledStepStore.swift
//  BakePlannerCore
//
//  The scheduled steps of all plans as the planning logic sees them: plain
//  values and the handful of queries planning needs, without saying where
//  they are kept. On iOS that is Core Data (CoreDataScheduledStepStore);
//  tests use a store in memory, and another platform can bring its own.
//

import Foundation

/// One scheduled step of a plan — the same fields as the Core Data entity
/// `NextStep`, as a plain value.
public struct ScheduledStepData: Equatable {
    /// `nil` only on steps stored before they had an id.
    public var id: UUID?
    /// Groups the steps of one planning run; `nil` on steps planned before
    /// plans had an id.
    public var planID: UUID?
    public var recipeName: String
    public var instruction: String
    public var step: Double
    /// Minutes after the plan's start.
    public var startTime: Int
    public var duration: Int
    public var date: Date
    /// Queued by `RecurringBakePlanner` rather than by the user.
    public var isAutomaticRecurrence: Bool
    /// The serving scale the plan was made at; `0` on steps planned before
    /// it was recorded.
    public var servingScale: Double

    public init(id: UUID? = nil, planID: UUID? = nil, recipeName: String, instruction: String, step: Double, startTime: Int, duration: Int, date: Date, isAutomaticRecurrence: Bool, servingScale: Double) {
        self.id = id
        self.planID = planID
        self.recipeName = recipeName
        self.instruction = instruction
        self.step = step
        self.startTime = startTime
        self.duration = duration
        self.date = date
        self.isAutomaticRecurrence = isAutomaticRecurrence
        self.servingScale = servingScale
    }
}

extension ScheduledStepData {
    /// Whether the step should already be shown; see
    /// `RecurringBakePlanner.isVisible(date:isAutomaticRecurrence:at:)`.
    public func isVisible(at now: Date = Date()) -> Bool {
        RecurringBakePlanner.isVisible(date: date, isAutomaticRecurrence: isAutomaticRecurrence, at: now)
    }
}

/// A scheduled step with the store's own key for it — steps stored before
/// they had an id need one too, to be marked done.
public struct StoredScheduledStep: Equatable {
    public var key: String
    public var data: ScheduledStepData

    public init(key: String, data: ScheduledStepData) {
        self.key = key
        self.data = data
    }
}

/// Where the scheduled steps are kept. A plan belongs to its recipe by
/// name; a recipe has at most one plan, which planning anew replaces.
public protocol ScheduledStepStore {
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
    /// Every scheduled step, by date and, at the same time, by step number.
    func allSteps() -> [StoredScheduledStep]
    /// Deletes the step with this key — the step is done — and saves.
    /// Nothing happens for an unknown key.
    func removeStep(key: String)
    /// Gives the steps new dates, by key, in one go — a step moved with its
    /// followers (see ScheduledStepShift) — and saves. Unknown keys are
    /// left out.
    func setDates(_ dates: [String: Date])
}

extension BakePlan {
    /// Every step of the plan, the generated ones included, as the scheduled
    /// steps to store for it. `servingScale` is the factor the plan was made
    /// at, so the plan's ingredient lists show the amounts that are actually
    /// weighed out. `isAutomaticRecurrence` marks steps queued by
    /// `RecurringBakePlanner` rather than by the user.
    public func scheduledStepData(planID: UUID, servingScale: Double,
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

    public func issues(from store: any ScheduledStepStore) -> [BakePlanIssue] {
        issues(existingWindows: BakePlanValidator.scheduledBakeWindows(excluding: recipeName, from: store))
    }

    /// The findings when this plan is kept in addition to the recipe's
    /// earlier plans ("Zusätzlich planen"): checked against every scheduled
    /// bake, those of the same recipe included — two loaves of one recipe
    /// need two ovens as much as two different ones.
    public func additionalPlanIssues(from store: any ScheduledStepStore) -> [BakePlanIssue] {
        issues(existingWindows: BakePlanValidator.scheduledBakeWindows(from: store))
    }
}

extension BakePlanValidator {
    /// The oven phases of all plans that are currently scheduled, without the
    /// plan of `recipeName` (which is about to be replaced) and without bakes
    /// that are already over.
    public static func scheduledBakeWindows(
        excluding recipeName: String,
        from store: any ScheduledStepStore,
        now: Date = Date()
    ) -> [BakeWindow] {
        bakeWindows(of: store.steps(excludingRecipe: recipeName), now: now)
    }

    /// The oven phases of all plans that are currently scheduled, every
    /// recipe's, without bakes that are already over.
    public static func scheduledBakeWindows(
        from store: any ScheduledStepStore,
        now: Date = Date()
    ) -> [BakeWindow] {
        bakeWindows(of: store.allSteps().map(\.data), now: now)
    }

    /// One oven phase per plan, by its plan ID. Grouping by recipe name, as
    /// before, mixed two plans of one recipe into a single phase — the bake
    /// of one and the end of the other, or none at all. Steps planned before
    /// plans had an ID still belong together by recipe.
    static func bakeWindows(of steps: [ScheduledStepData], now: Date) -> [BakeWindow] {
        Dictionary(grouping: steps, by: { $0.planID?.uuidString ?? "recipe:" + $0.recipeName })
            .compactMap { _, steps in
                bakeWindow(
                    recipeName: steps[0].recipeName,
                    steps: steps.map {
                        PlannedStep(instruction: $0.instruction, step: $0.step, date: $0.date)
                    }
                )
            }
            .filter { $0.end > now }
            .sorted { $0.start < $1.start }
    }
}

extension BakePlanAdvisor {
    /// The suggestions for the baking views: the day window from the
    /// settings, nothing before now or beyond the picker's range, and the
    /// bakes already scheduled.
    public static func nightFreeDates(for plan: BakePlan, from store: any ScheduledStepStore,
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
