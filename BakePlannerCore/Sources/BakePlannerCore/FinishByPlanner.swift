//
//  FinishByPlanner.swift
//  BakePlannerCore
//
//  "Fertig bis …" in the recipe list: for a chosen finish, whether a recipe
//  can still be made from now and when it would have to start. The plan is
//  the same BakePlan the baking view works out in "Fertig bis" mode, so the
//  start shown in the list is the start the plan sheet will propose.
//

import Foundation

/// What a recipe needs to be finished by a chosen time.
public struct FinishByOutcome: Equatable, Sendable {
    /// When the first step — the recipe's or the generated oven step — begins.
    public let start: Date
    /// Minutes from the start to the chosen finish.
    public let totalMinutes: Int
    /// Whether a step begins outside the day window of the settings.
    public let hasNightSteps: Bool

    public init(start: Date, totalMinutes: Int, hasNightSteps: Bool) {
        self.start = start
        self.totalMinutes = totalMinutes
        self.hasNightSteps = hasNightSteps
    }
}

public enum FinishByPlanner {

    /// The plan that finishes at `finishBy`, or nil for a recipe without
    /// timed steps. Steps stored without start times (an import that never
    /// went through the editor) follow one another.
    public static func plan(for recipe: RecipeExportData, finishBy: Date, languageCode: String = "de",
                            preheatTime: Int = GlobalVariables.preheatTime,
                            stonePreheatTime: Int = GlobalVariables.stonePreheatTime,
                            calendar: Calendar = .current) -> BakePlan? {
        let ordered = recipe.instructions.sorted { $0.step < $1.step }
        let sequential = ordered.count > 1 && ordered.allSatisfy { $0.startTime == 0 }
        var clock = 0
        let steps = ordered.map { instruction -> PlanStep in
            let start = sequential ? clock : max(0, instruction.startTime)
            let duration = max(0, instruction.duration)
            clock = start + duration
            let window: ClosedRange<Int>? = {
                guard let lower = instruction.minDuration, let upper = instruction.maxDuration, lower <= upper else { return nil }
                return lower...upper
            }()
            return PlanStep(instruction: instruction.instruction, step: instruction.step,
                            startTime: start, duration: duration,
                            componentName: instruction.componentName, durationWindow: window,
                            oven: instruction.oven)
        }
        guard steps.contains(where: { $0.duration > 0 }) else { return nil }
        return BakePlan(recipeName: recipe.name, steps: steps, prepTime: recipe.prepTime,
                        anchor: .finishesBy, date: finishBy, languageCode: languageCode,
                        preheatTime: preheatTime, stonePreheatTime: stonePreheatTime, calendar: calendar)
    }

    /// When the recipe would have to start to be finished by `finishBy`, or
    /// nil when it cannot be made any more: the start lies before `now`, or
    /// the recipe has no timed steps.
    public static func outcome(for recipe: RecipeExportData, finishBy: Date, now: Date,
                               dayStart: Int = GlobalVariables.dayStart, dayEnd: Int = GlobalVariables.dayEnd,
                               languageCode: String = "de",
                               preheatTime: Int = GlobalVariables.preheatTime,
                               stonePreheatTime: Int = GlobalVariables.stonePreheatTime,
                               calendar: Calendar = .current) -> FinishByOutcome? {
        guard let plan = plan(for: recipe, finishBy: finishBy, languageCode: languageCode,
                              preheatTime: preheatTime, stonePreheatTime: stonePreheatTime, calendar: calendar) else {
            return nil
        }
        // The generated oven step may precede the recipe's first step when
        // the bake comes first; the start is whichever comes first.
        let start = plan.plannedSteps.map(\.date).min() ?? plan.baseDate
        guard start >= now else { return nil }
        let minutes = Int((finishBy.timeIntervalSince(start) / 60).rounded())
        return FinishByOutcome(start: start, totalMinutes: minutes,
                               hasNightSteps: BakePlanAdvisor.hasNightSteps(plan, dayStart: dayStart, dayEnd: dayEnd))
    }

    /// The finish "Für morgen früh" aims at: tomorrow at half past seven, or
    /// half past the day's start when the day begins later than that.
    public static func morningFinish(after now: Date, dayStart: Int = GlobalVariables.dayStart,
                                     calendar: Calendar = .current) -> Date {
        let hour = max(7, dayStart)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: hour, minute: 30, second: 0, of: tomorrow) ?? tomorrow
    }
}
