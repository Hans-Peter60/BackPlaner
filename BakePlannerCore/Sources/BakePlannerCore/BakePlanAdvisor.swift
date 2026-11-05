//
//  BakePlanAdvisor.swift
//  BakePlannerCore
//
//  The plan check only says what is wrong with a date: steps in the night,
//  a bake that needs an oven already taken, a pause too short. The advisor
//  looks for the nearest earlier and the nearest later date at which the
//  plan is free of that, so the baking views can offer them with a single
//  tap. The recipe stays as it is: only the date in the scheduling controls
//  moves. Two questions are asked of it: a date at which no step begins at
//  night, and — on a baking day with several loaves — a date at which the
//  ovens come free one after another.
//

import Foundation

/// A date for the scheduling controls the advisor suggests.
public struct PlanDateSuggestion: Equatable, Identifiable {
    /// The new date for the picker, read like the current one ("Starten ab"
    /// or "Fertig bis").
    public let date: Date
    /// Minutes from the current date; negative means earlier.
    public let shift: Int
    /// When the first step begins and the bake is finished with this date.
    public let start: Date
    public let finish: Date

    public var id: Date { date }

    public init(date: Date, shift: Int, start: Date, finish: Date) {
        self.date = date
        self.shift = shift
        self.start = start
        self.finish = finish
    }
}

/// The name the suggestions carried while there was only the question of
/// the night.
public typealias NightFreeDate = PlanDateSuggestion

public enum BakePlanAdvisor {

    /// Suggested dates lie on the quarter hour.
    public static let gridMinutes = 15
    /// How far the search reaches in either direction. A day is enough: one
    /// day later the steps fall on the same clock times again.
    public static let searchMinutes = 24 * 60

    // MARK: Night

    /// The nearest earlier and the nearest later date at which every step of
    /// `plan` begins inside the day window, the closer one first. Empty when
    /// the plan already fits, or when no date within a day either way does.
    ///
    /// - Parameters:
    ///   - dayStart, dayEnd: the day window in hours, as in the settings.
    ///   - allowedDates: the range of the date picker; nothing outside it is
    ///     suggested, so the plan never starts in the past.
    ///   - existingWindows: the oven phases already scheduled. A date at which
    ///     this bake would need more ovens than there are is skipped.
    ///   - ovenCount: how many bakes may run at once.
    public static func nightFreeDates(
        for plan: BakePlan,
        dayStart: Int,
        dayEnd: Int,
        allowedDates: ClosedRange<Date>,
        existingWindows: [BakeWindow] = [],
        ovenCount: Int = 1
    ) -> [PlanDateSuggestion] {
        guard hasNightSteps(plan, dayStart: dayStart, dayEnd: dayEnd) else { return [] }

        return nearestDates(for: plan, allowedDates: allowedDates) { moved in
            guard !hasNightSteps(moved, dayStart: dayStart, dayEnd: dayEnd) else { return false }
            if let window = moved.bakeWindow,
               BakePlanValidator.needsMoreOvens(window, existingWindows: existingWindows, ovenCount: ovenCount) {
                return false
            }
            return true
        }
    }

    /// Whether a step begins outside the day window set in the settings.
    public static func hasNightSteps(_ plan: BakePlan) -> Bool {
        let (dayStart, dayEnd) = BakePlanValidator.dayWindow()
        return hasNightSteps(plan, dayStart: dayStart, dayEnd: dayEnd)
    }

    /// Whether any step of the plan, the generated ones included, begins
    /// outside the day window.
    public static func hasNightSteps(_ plan: BakePlan, dayStart: Int, dayEnd: Int) -> Bool {
        plan.plannedSteps.contains {
            BakePlanValidator.isOutsideDay($0.date, dayStart: dayStart, dayEnd: dayEnd, calendar: plan.calendar)
        }
    }

    // MARK: Baking day

    /// Whether the plan's bake clashes with the bakes already scheduled: more
    /// bakes at once than there are ovens, or two bakes in one oven closer
    /// than the pause (`BakePlanValidator.fitsOvens`). A plan without a bake,
    /// such as feeding a starter, never clashes.
    public static func hasOvenConflict(
        _ plan: BakePlan,
        existingWindows: [BakeWindow],
        ovenCount: Int,
        bakePause: Int
    ) -> Bool {
        guard let window = plan.bakeWindow else { return false }
        return !BakePlanValidator.fitsOvens(window, existingWindows: existingWindows,
                                            ovenCount: ovenCount, bakePause: bakePause)
    }

    /// The nearest earlier and the nearest later date at which the plan's
    /// bake fits the ovens beside the bakes already scheduled — no more at
    /// once than there are ovens, the pause between two bakes kept — the
    /// closer one first. This is how a second loaf finds its place on a
    /// baking day: the app says when it has to start so the oven is free
    /// when the dough is ready.
    ///
    /// Dates at which no step begins at night either are preferred; only
    /// when there is none within reach does the search accept night steps.
    /// Empty when the plan already fits, or when no date within a day
    /// either way does.
    public static func ovenFreeDates(
        for plan: BakePlan,
        dayStart: Int,
        dayEnd: Int,
        allowedDates: ClosedRange<Date>,
        existingWindows: [BakeWindow],
        ovenCount: Int,
        bakePause: Int
    ) -> [PlanDateSuggestion] {
        guard hasOvenConflict(plan, existingWindows: existingWindows, ovenCount: ovenCount, bakePause: bakePause)
        else { return [] }

        func fitsOvens(_ moved: BakePlan) -> Bool {
            guard let window = moved.bakeWindow else { return false }
            return BakePlanValidator.fitsOvens(window, existingWindows: existingWindows,
                                               ovenCount: ovenCount, bakePause: bakePause)
        }

        let inDaylight = nearestDates(for: plan, allowedDates: allowedDates) { moved in
            fitsOvens(moved) && !hasNightSteps(moved, dayStart: dayStart, dayEnd: dayEnd)
        }
        if !inDaylight.isEmpty { return inDaylight }
        return nearestDates(for: plan, allowedDates: allowedDates, accepting: fitsOvens)
    }

    // MARK: Search

    /// The nearest earlier and the nearest later date on the quarter-hour
    /// grid, within `allowedDates` and a day either way, at which the moved
    /// plan passes `accepting`; the closer one first.
    private static func nearestDates(
        for plan: BakePlan,
        allowedDates: ClosedRange<Date>,
        accepting: (BakePlan) -> Bool
    ) -> [PlanDateSuggestion] {
        let calendar = plan.calendar
        let grid = quarterHour(atOrBefore: plan.date, calendar: calendar)

        func candidate(_ offset: Int) -> PlanDateSuggestion? {
            guard let date = calendar.date(byAdding: .minute, value: offset, to: grid),
                  date != plan.date,
                  allowedDates.contains(date) else { return nil }

            let moved = plan.moved(to: date)
            guard allowedDates.contains(moved.baseDate), accepting(moved) else { return nil }

            let shift = Int(date.timeIntervalSince(plan.date) / 60)
            return PlanDateSuggestion(date: date, shift: shift, start: moved.baseDate,
                                      finish: moved.date(of: moved.endStep))
        }

        let steps = searchMinutes / gridMinutes
        // The grid point itself lies at or before the current date, so the
        // earlier search starts there and the later one a quarter hour on.
        var earlier: PlanDateSuggestion?
        for step in 0...steps {
            if let found = candidate(-step * gridMinutes) { earlier = found; break }
        }
        var later: PlanDateSuggestion?
        for step in 1...steps {
            if let found = candidate(step * gridMinutes) { later = found; break }
        }

        return [earlier, later]
            .compactMap { $0 }
            .sorted { abs($0.shift) < abs($1.shift) }
    }

    private static func quarterHour(atOrBefore date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var rounded = components
        rounded.minute = (components.minute ?? 0) / gridMinutes * gridMinutes
        return calendar.date(from: rounded) ?? date
    }
}
