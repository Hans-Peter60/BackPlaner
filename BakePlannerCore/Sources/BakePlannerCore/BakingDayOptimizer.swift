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
    /// A kneading, folding or shaping step coincides with one of another
    /// bread or of a plan already scheduled — two pairs of hands needed.
    public let overlapsWork: Bool

    public init(id: String, recipeName: String, plan: BakePlan, hasNightSteps: Bool, conflictsWithOvens: Bool,
                overlapsWork: Bool = false) {
        self.id = id
        self.recipeName = recipeName
        self.plan = plan
        self.hasNightSteps = hasNightSteps
        self.conflictsWithOvens = conflictsWithOvens
        self.overlapsWork = overlapsWork
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

    /// Hands-on work never lasts longer than this at a stretch: a step that
    /// mixes and then ripens for hours, or rests with a fold or two in it,
    /// keeps the hands only at its start.
    public static let handsOnMinutes = 30
    /// A marker without a duration — "Dehnen und falten" — takes this long.
    public static let markerMinutes = 5

    /// The time with the hands in the dough, when the step has any:
    /// kneading, folding, shaping, or a short step of no clear kind, each
    /// for its duration up to `handsOnMinutes` from its start. Rests, cold
    /// rests, oven steps and longer steps of no clear kind are none.
    public static func workInterval(instruction: String, duration: Int, date: Date) -> DateInterval? {
        let kind = PlanTimelineLane.kind(of: instruction, duration: duration)
        switch kind {
        case .mix, .fold, .shape:
            break
        case .other:
            guard duration <= handsOnMinutes, !ProofTiming.isColdStep(instruction) else { return nil }
        case .rest, .oven, .bake:
            return nil
        }
        let minutes = min(max(duration, markerMinutes), handsOnMinutes)
        return DateInterval(start: date, duration: TimeInterval(minutes * 60))
    }

    /// The hands-on intervals of a plan, the recipe's steps only.
    static func workIntervals(of plan: BakePlan) -> [DateInterval] {
        plan.scheduledSteps.compactMap { workInterval(instruction: $0.instruction, duration: $0.duration, date: plan.date(of: $0)) }
    }

    /// Two work intervals clash when they share time; one ending as the
    /// other begins is fine (`DateInterval.intersects` would count it).
    /// Whether a hands-on step begins outside the day window. Rests at night
    /// are what a long bread does; kneading at three in the morning is what
    /// the search avoids.
    static func hasNightWork(_ plan: BakePlan, dayStart: Int, dayEnd: Int) -> Bool {
        plan.scheduledSteps.contains { step in
            let date = plan.date(of: step)
            guard workInterval(instruction: step.instruction, duration: step.duration, date: date) != nil else { return false }
            return BakePlanValidator.isOutsideDay(date, dayStart: dayStart, dayEnd: dayEnd, calendar: plan.calendar)
        }
    }

    static func overlapsWork(_ plan: BakePlan, busy: [DateInterval]) -> Bool {
        let mine = workIntervals(of: plan)
        return mine.contains { interval in
            busy.contains { $0.start < interval.end && interval.start < $0.end }
        }
    }

    /// Places the candidates before `finishBy`. The bread with the longest
    /// bake is placed first, at the wished time; every further bread takes
    /// the latest quarter-hour finish at which its bake still fits the
    /// ovens beside the breads placed so far and the bakes already
    /// scheduled. Among the fitting finishes, the nearest one at which no
    /// kneading, folding or shaping coincides with another bread's (or with
    /// a step already scheduled, `existingWork`) and no hands-on step falls
    /// into the night is preferred, then the nearest without the hands
    /// clashing, then the nearest without work at night. Rests at night do
    /// not count: a long bread sleeps through the night anyway. Breads
    /// without a bake (a starter being fed) finish at the wished time as
    /// well.
    public static func schedule(_ candidates: [BakingDayCandidate], finishBy: Date, now: Date,
                                ovenCount: Int, bakePause: Int, dayStart: Int, dayEnd: Int,
                                existingWindows: [BakeWindow], existingWork: [DateInterval] = [],
                                languageCode: String = "de",
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
        var busy = existingWork
        var placements: [BakingDayPlacement] = []
        for (candidate, plan) in ordered {
            let placed = place(plan, finishBy: finishBy, now: now, placedWindows: placedWindows, busy: busy, ovenCount: ovenCount,
                               bakePause: bakePause, dayStart: dayStart, dayEnd: dayEnd, calendar: calendar)
            if let window = placed.plan.bakeWindow { placedWindows.append(window) }
            let clashes = overlapsWork(placed.plan, busy: busy)
            busy += workIntervals(of: placed.plan)
            placements.append(BakingDayPlacement(id: candidate.id, recipeName: candidate.recipe.name, plan: placed.plan,
                                                 hasNightSteps: BakePlanAdvisor.hasNightSteps(placed.plan, dayStart: dayStart, dayEnd: dayEnd),
                                                 conflictsWithOvens: placed.conflicts, overlapsWork: clashes))
        }
        return BakingDaySchedule(placements: placements.sorted { $0.start < $1.start }, unplaced: unplaced)
    }

    /// The latest finish at or before the wished time, on the quarter
    /// hour, at which the bake fits the ovens: first one where the hands
    /// are free and no hands-on step falls into the night, then one with
    /// free hands, then one without work at night, then any; the wished
    /// time with a conflict when nothing within a day fits the ovens.
    private static func place(_ plan: BakePlan, finishBy: Date, now: Date, placedWindows: [BakeWindow], busy: [DateInterval],
                              ovenCount: Int, bakePause: Int, dayStart: Int, dayEnd: Int,
                              calendar: Calendar) -> (plan: BakePlan, conflicts: Bool) {
        func fits(_ moved: BakePlan) -> Bool {
            guard let window = moved.bakeWindow else { return true }
            return BakePlanValidator.fitsOvens(window, existingWindows: placedWindows, ovenCount: ovenCount, bakePause: bakePause)
        }
        func night(_ moved: BakePlan) -> Bool { hasNightWork(moved, dayStart: dayStart, dayEnd: dayEnd) }
        func hands(_ moved: BakePlan) -> Bool { overlapsWork(moved, busy: busy) }

        // The wished time itself, then every quarter hour before it — as
        // long as the bread could still be started: a finish whose start
        // lies in the past is no way out, only the wished time may show
        // that and be flagged.
        func start(of moved: BakePlan) -> Date { moved.plannedSteps.map(\.date).min() ?? moved.baseDate }
        var candidates = [plan]
        let grid = BakePlanAdvisor.gridMinutes
        let first = quarterHour(atOrBefore: finishBy, calendar: calendar)
        var offset = 0
        while offset <= searchMinutes {
            if let date = calendar.date(byAdding: .minute, value: -offset, to: first), date < finishBy {
                let moved = plan.moved(to: date)
                if start(of: moved) < now { break }
                candidates.append(moved)
            }
            offset += grid
        }
        let fitting = candidates.filter(fits)
        guard !fitting.isEmpty else { return (plan, true) }
        // The wished time is kept whenever the ovens fit and the hands are
        // free — night steps alone do not move a bread away from it.
        if fitting[0].date == plan.date, !hands(plan) { return (plan, false) }
        if let best = fitting.first(where: { !hands($0) && !night($0) }) { return (best, false) }
        if let free = fitting.first(where: { !hands($0) }) { return (free, false) }
        if let daylight = fitting.first(where: { !night($0) }) { return (daylight, false) }
        return (fitting[0], false)
    }

    private static func quarterHour(atOrBefore date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.minute = (components.minute ?? 0) / BakePlanAdvisor.gridMinutes * BakePlanAdvisor.gridMinutes
        return calendar.date(from: components) ?? date
    }
}
