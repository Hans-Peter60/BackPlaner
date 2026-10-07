//
//  BakePlanAdvisor.swift
//  BackPlaner
//
//  When a plan has steps that begin before Tagesbeginn or after Tagesende,
//  the plan check only says so. The advisor looks for the nearest earlier and
//  the nearest later date for the same plan at which every step begins inside
//  the day, so the baking view can offer them with a single tap. The recipe
//  stays as it is: only the date in the scheduling controls moves.
//

import Foundation
import CoreData

/// A date for the scheduling controls at which no step of the plan begins at
/// night.
struct NightFreeDate: Equatable, Identifiable {
    /// The new date for the picker, read like the current one ("Starten ab"
    /// or "Fertig bis").
    let date: Date
    /// Minutes from the current date; negative means earlier.
    let shift: Int
    /// When the first step begins and the bake is finished with this date.
    let start: Date
    let finish: Date

    var id: Date { date }
}

enum BakePlanAdvisor {

    /// Suggested dates lie on the quarter hour.
    static let gridMinutes = 15
    /// How far the search reaches in either direction. A day is enough: one
    /// day later the steps fall on the same clock times again.
    static let searchMinutes = 24 * 60

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
    static func nightFreeDates(
        for plan: BakePlan,
        dayStart: Int,
        dayEnd: Int,
        allowedDates: ClosedRange<Date>,
        existingWindows: [BakeWindow] = [],
        ovenCount: Int = 1
    ) -> [NightFreeDate] {

        guard hasNightSteps(plan, dayStart: dayStart, dayEnd: dayEnd) else { return [] }

        let calendar = plan.calendar
        let grid = quarterHour(atOrBefore: plan.date, calendar: calendar)

        func candidate(_ offset: Int) -> NightFreeDate? {
            guard let date = calendar.date(byAdding: .minute, value: offset, to: grid),
                  date != plan.date,
                  allowedDates.contains(date) else { return nil }

            let moved = plan.moved(to: date)
            guard allowedDates.contains(moved.baseDate),
                  !hasNightSteps(moved, dayStart: dayStart, dayEnd: dayEnd) else { return nil }
            if let window = moved.bakeWindow,
               BakePlanValidator.needsMoreOvens(window, existingWindows: existingWindows, ovenCount: ovenCount) {
                return nil
            }

            let shift = Int(date.timeIntervalSince(plan.date) / 60)
            return NightFreeDate(date: date, shift: shift, start: moved.baseDate,
                                 finish: moved.date(of: moved.endStep))
        }

        let steps = searchMinutes / gridMinutes
        // The grid point itself lies at or before the current date, so the
        // earlier search starts there and the later one a quarter hour on.
        let earlier = (0...steps).lazy.compactMap { candidate(-$0 * gridMinutes) }.first
        let later   = (1...steps).lazy.compactMap { candidate($0 * gridMinutes) }.first

        return [earlier, later]
            .compactMap { $0 }
            .sorted { abs($0.shift) < abs($1.shift) }
    }

    /// The suggestions for the baking views: the day window from the
    /// settings, nothing before now or beyond the picker's range, and the
    /// bakes already scheduled.
    static func nightFreeDates(for plan: BakePlan, in context: NSManagedObjectContext,
                               now: Date = Date()) -> [NightFreeDate] {
        let (dayStart, dayEnd) = BakePlanValidator.dayWindow()
        let range = GlobalVariables.planningDateRange(around: now)
        guard now < range.upperBound else { return [] }
        return nightFreeDates(
            for: plan, dayStart: dayStart, dayEnd: dayEnd,
            allowedDates: now...range.upperBound,
            existingWindows: BakePlanValidator.scheduledBakeWindows(excluding: plan.recipeName, in: context),
            ovenCount: GlobalVariables.ovenCount
        )
    }

    /// Whether a step begins outside the day window set in the settings.
    static func hasNightSteps(_ plan: BakePlan) -> Bool {
        let (dayStart, dayEnd) = BakePlanValidator.dayWindow()
        return hasNightSteps(plan, dayStart: dayStart, dayEnd: dayEnd)
    }

    /// Whether any step of the plan, the generated ones included, begins
    /// outside the day window.
    static func hasNightSteps(_ plan: BakePlan, dayStart: Int, dayEnd: Int) -> Bool {
        plan.plannedSteps.contains {
            BakePlanValidator.isOutsideDay($0.date, dayStart: dayStart, dayEnd: dayEnd, calendar: plan.calendar)
        }
    }

    private static func quarterHour(atOrBefore date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var rounded = components
        rounded.minute = (components.minute ?? 0) / gridMinutes * gridMinutes
        return calendar.date(from: rounded) ?? date
    }
}
