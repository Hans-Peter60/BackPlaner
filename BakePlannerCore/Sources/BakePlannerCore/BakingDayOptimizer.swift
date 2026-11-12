//
//  BakingDayOptimizer.swift
//  BakePlannerCore
//
//  A baking day with several breads: the last one finished at the wished
//  time, the others placed before it so that no more bakes run at once
//  than there are ovens and the pause between two bakes in one oven is
//  kept. Every bread's plan is the BakePlan the baking view would make in
//  "Fertig bis" mode, so what is shown here is what gets scheduled.
//

import Foundation

/// A recipe to place on the baking day.
public struct BakingDayCandidate: Identifiable, Equatable {
    public let id: String
    public let recipe: RecipeExportData

    public init(id: String, recipe: RecipeExportData) {
        self.id = id
        self.recipe = recipe
    }
}

/// One bread on the baking day: its plan, and what to watch.
public struct BakingDayPlacement: Identifiable {
    public let id: String
    public let recipeName: String
    public let plan: BakePlan
    /// Whether a step begins outside the day window.
    public let hasNightSteps: Bool
    /// No finish within a day before the wished time fitted the ovens; the
    /// bread sits at the wished time regardless and the person decides.
    public let conflictsWithOvens: Bool

    public init(id: String, recipeName: String, plan: BakePlan, hasNightSteps: Bool, conflictsWithOvens: Bool) {
        self.id = id
        self.recipeName = recipeName
        self.plan = plan
        self.hasNightSteps = hasNightSteps
        self.conflictsWithOvens = conflictsWithOvens
    }

    /// When the first step — the recipe's or the generated oven step — begins.
    public var start: Date { plan.plannedSteps.map(\.date).min() ?? plan.baseDate }
    /// When the bread is finished.
    public var finish: Date { plan.date }
    public var bakeWindow: BakeWindow? { plan.bakeWindow }
    /// Whether the plan would have to have started already.
    public func startsInThePast(now: Date) -> Bool { start < now }
}

/// The baking day as worked out.
public struct BakingDaySchedule {
    /// The breads placed, earliest start first.
    public let placements: [BakingDayPlacement]
    /// Recipes without timed steps, which cannot be placed.
    public let unplaced: [BakingDayCandidate]

    public init(placements: [BakingDayPlacement], unplaced: [BakingDayCandidate]) {
        self.placements = placements
        self.unplaced = unplaced
    }

    /// Everything fits the ovens and nothing has to start in the past.
    public func isClean(now: Date) -> Bool {
        placements.allSatisfy { !$0.conflictsWithOvens && !$0.startsInThePast(now: now) }
    }
}

public enum BakingDayOptimizer {

    /// How far before the wished finish a bread may be moved to fit.
    public static let searchMinutes = 24 * 60

    /// Places the candidates before `finishBy`. The bread with the longest
    /// bake is placed first, at the wished time; every further bread takes
    /// the latest quarter-hour finish at which its bake still fits the
    /// ovens beside the breads placed so far and the bakes already
    /// scheduled — a finish without night steps preferred. Breads without a
    /// bake (a starter being fed) finish at the wished time as well.
    public static func schedule(_ candidates: [BakingDayCandidate], finishBy: Date, now: Date,
                                ovenCount: Int, bakePause: Int, dayStart: Int, dayEnd: Int,
                                existingWindows: [BakeWindow], languageCode: String = "de",
                                preheatTime: Int = GlobalVariables.preheatTime,
                                stonePreheatTime: Int = GlobalVariables.stonePreheatTime,
                                calendar: Calendar = .current) -> BakingDaySchedule {
        var plans: [(candidate: BakingDayCandidate, plan: BakePlan)] = []
        var unplaced: [BakingDayCandidate] = []
        for candidate in candidates {
            if let plan = FinishByPlanner.plan(for: candidate.recipe, finishBy: finishBy, languageCode: languageCode,
                                               preheatTime: preheatTime, stonePreheatTime: stonePreheatTime,
                                               calendar: calendar) {
                plans.append((candidate, plan))
            } else {
                unplaced.append(candidate)
            }
        }
        // Longest bake first: it takes the wished time, the shorter ones
        // slot in before it.
        let ordered = plans.sorted { a, b in
            let bakeA = a.plan.bakeWindow.map { $0.end.timeIntervalSince($0.start) } ?? -1
            let bakeB = b.plan.bakeWindow.map { $0.end.timeIntervalSince($0.start) } ?? -1
            if bakeA != bakeB { return bakeA > bakeB }
            return a.plan.totalMinutes > b.plan.totalMinutes
        }

        var placedWindows = existingWindows
        var placements: [BakingDayPlacement] = []
        for (candidate, plan) in ordered {
            let placed = place(plan, finishBy: finishBy, placedWindows: placedWindows, ovenCount: ovenCount,
                               bakePause: bakePause, dayStart: dayStart, dayEnd: dayEnd, calendar: calendar)
            if let window = placed.plan.bakeWindow { placedWindows.append(window) }
            placements.append(BakingDayPlacement(id: candidate.id, recipeName: candidate.recipe.name, plan: placed.plan,
                                                 hasNightSteps: BakePlanAdvisor.hasNightSteps(placed.plan, dayStart: dayStart, dayEnd: dayEnd),
                                                 conflictsWithOvens: placed.conflicts))
        }
        return BakingDaySchedule(placements: placements.sorted { $0.start < $1.start }, unplaced: unplaced)
    }

    /// The wished time itself when the bake fits there; else the latest
    /// earlier finish on the quarter hour at which it fits — one without
    /// night steps preferred — and the wished time with a conflict when
    /// nothing within a day fits.
    private static func place(_ plan: BakePlan, finishBy: Date, placedWindows: [BakeWindow], ovenCount: Int,
                              bakePause: Int, dayStart: Int, dayEnd: Int, calendar: Calendar) -> (plan: BakePlan, conflicts: Bool) {
        guard plan.bakeWindow != nil else { return (plan, false) }

        func fits(_ moved: BakePlan) -> Bool {
            guard let window = moved.bakeWindow else { return true }
            return BakePlanValidator.fitsOvens(window, existingWindows: placedWindows, ovenCount: ovenCount, bakePause: bakePause)
        }
        if fits(plan) { return (plan, false) }
        func candidates() -> [BakePlan] {
            var result: [BakePlan] = []
            let grid = BakePlanAdvisor.gridMinutes
            let first = quarterHour(atOrBefore: finishBy, calendar: calendar)
            var offset = 0
            while offset <= searchMinutes {
                if let date = calendar.date(byAdding: .minute, value: -offset, to: first), date < finishBy {
                    result.append(plan.moved(to: date))
                }
                offset += grid
            }
            return result
        }
        let all = candidates()
        if let daylight = all.first(where: { fits($0) && !BakePlanAdvisor.hasNightSteps($0, dayStart: dayStart, dayEnd: dayEnd) }) {
            return (daylight, false)
        }
        if let any = all.first(where: fits) {
            return (any, false)
        }
        return (plan, true)
    }

    private static func quarterHour(atOrBefore date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.minute = (components.minute ?? 0) / BakePlanAdvisor.gridMinutes * BakePlanAdvisor.gridMinutes
        return calendar.date(from: components) ?? date
    }
}
