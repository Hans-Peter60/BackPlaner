//
//  RecurringBakePlannerTests.swift
//  BackPlanerTests
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("The next occurrence of a recipe that refreshes on a fixed rhythm")
struct RecurringBakePlannerTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test("Due at the very next multiple of the interval")
    func dueAtTheFirstMultiple() {
        let lastFinish = date(2026, 10, 1, 10)
        let now        = date(2026, 10, 2, 8)
        let finish = RecurringBakePlanner.nextFinishDate(lastFinish: lastFinish, intervalDays: 5,
                                                         prepTime: 0, now: now, calendar: calendar)
        #expect(finish == date(2026, 10, 6, 10))
    }

    @Test("Several missed cycles land on the rhythm's grid, not on \"now\"")
    func missedCyclesStayOnTheGrid() {
        let lastFinish = date(2026, 10, 1, 10)
        // 17 days later: cycles due on the 6th, 11th and 16th were all
        // missed. The next slot on the original grid is the 21st, not
        // "today" or "tomorrow".
        let now = date(2026, 10, 18, 9)
        let finish = RecurringBakePlanner.nextFinishDate(lastFinish: lastFinish, intervalDays: 5,
                                                          prepTime: 0, now: now, calendar: calendar)
        #expect(finish == date(2026, 10, 21, 10))
    }

    @Test("A plan whose start already lies in the past but whose finish is still ahead steps to the next cycle")
    func startInThePastStepsForward() {
        // The very next multiple's plan starts 18 hours before it finishes
        // (prepTime). "Now" falls inside that window, after the start but
        // before the finish, so that cycle no longer leaves room to plan —
        // the occurrence must be the one after it.
        let lastFinish = date(2026, 10, 1, 10)
        let now        = date(2026, 10, 6, 6)
        let finish = RecurringBakePlanner.nextFinishDate(lastFinish: lastFinish, intervalDays: 5,
                                                          prepTime: 18 * 60, now: now, calendar: calendar)
        #expect(finish == date(2026, 10, 11, 10))
    }

    @Test("Disabled (intervalDays 0) never produces a date")
    func disabledIntervalReturnsNil() {
        let finish = RecurringBakePlanner.nextFinishDate(lastFinish: date(2026, 10, 1, 10), intervalDays: 0,
                                                         prepTime: 0, now: date(2026, 10, 1, 10), calendar: calendar)
        #expect(finish == nil)
    }

    @Test("The time of day survives a daylight-saving change")
    func survivesDaylightSavingChange() {
        // Clocks in Europe/Berlin go back on 2026-10-25. Stepping by
        // calendar days instead of fixed 86 400-second multiples keeps the
        // plan at 18:00 local time on both sides of the change.
        let lastFinish = date(2026, 10, 20, 18)
        let now        = date(2026, 10, 20, 19)
        let finish = RecurringBakePlanner.nextFinishDate(lastFinish: lastFinish, intervalDays: 7,
                                                         prepTime: 0, now: now, calendar: calendar)
        #expect(finish == date(2026, 10, 27, 18))
    }
}
