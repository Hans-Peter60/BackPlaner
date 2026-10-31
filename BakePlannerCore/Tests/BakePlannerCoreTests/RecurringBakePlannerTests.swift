//
//  RecurringBakePlannerTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

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
        let finish = RecurringBakePlanner.nextFinishDate(lastFinish: lastFinish, duration: 0,
                                                         intervalDays: 5, now: now, calendar: calendar)
        #expect(finish == date(2026, 10, 6, 10))
    }

    @Test("The next start shown is the slot after a pending plan, else the next slot, else nothing")
    func nextStartForTheViews() {
        let now = date(2026, 10, 2, 8)
        // A plan already queued wrote its finish into the bake history; the
        // rhythm continues after it.
        #expect(RecurringBakePlanner.nextStart(lastFinish: date(2026, 10, 4, 18), duration: 0, intervalDays: 5,
                                               now: now, calendar: calendar) == date(2026, 10, 9, 18))
        // A starter fed today at 05:20, ripe at 17:20, on a daily rhythm:
        // fed again tomorrow at 05:20.
        #expect(RecurringBakePlanner.nextStart(lastFinish: date(2026, 10, 2, 17, 20), duration: 12 * 60, intervalDays: 1,
                                               now: now, calendar: calendar) == date(2026, 10, 3, 5, 20))
        // Otherwise the rhythm from the last bake.
        #expect(RecurringBakePlanner.nextStart(lastFinish: date(2026, 10, 1, 10), duration: 0, intervalDays: 5,
                                               now: now, calendar: calendar) == date(2026, 10, 6, 10))
        // Nothing to measure from, or no rhythm.
        #expect(RecurringBakePlanner.nextStart(lastFinish: nil, duration: 0, intervalDays: 5,
                                               now: now, calendar: calendar) == nil)
        #expect(RecurringBakePlanner.nextStart(lastFinish: date(2026, 10, 1, 10), duration: 0, intervalDays: 0,
                                               now: now, calendar: calendar) == nil)
    }

    /// The rhythm hangs on the start, not the finish: a bread started at
    /// 08:00 is started at 08:00 again, however long it takes, and the
    /// finish follows from the recipe's length. Anchored on the finish, a
    /// recipe whose stored preparation time fell behind its steps used to
    /// shift its start.
    @Test("The first step keeps its time of day; the plan's length comes from the steps when prepTime fell behind")
    func startKeepsItsTimeOfDay() {
        let now = date(2026, 10, 2, 8)
        // Started on the 1st at 08:00, 26 hours long, finished on the 2nd at 10:00.
        let lastFinish = date(2026, 10, 2, 10)
        #expect(RecurringBakePlanner.nextStartDate(lastFinish: lastFinish, duration: 26 * 60, intervalDays: 5,
                                                   now: now, calendar: calendar) == date(2026, 10, 6, 8))
        #expect(RecurringBakePlanner.nextFinishDate(lastFinish: lastFinish, duration: 26 * 60, intervalDays: 5,
                                                    now: now, calendar: calendar) == date(2026, 10, 7, 10))
        // The length is the steps' end when the stored preparation time is shorter.
        #expect(RecurringBakePlanner.planDuration(prepTime: 60, stepEnds: [0 + 10, 10 + 720]) == 730)
        #expect(RecurringBakePlanner.planDuration(prepTime: 900, stepEnds: [10, 730]) == 900)
        #expect(RecurringBakePlanner.planDuration(prepTime: 0, stepEnds: []) == 0)
    }

    @Test("Several missed cycles land on the rhythm's grid, not on \"now\"")
    func missedCyclesStayOnTheGrid() {
        let lastFinish = date(2026, 10, 1, 10)
        // 17 days later: cycles due on the 6th, 11th and 16th were all
        // missed. The next slot on the original grid is the 21st, not
        // "today" or "tomorrow".
        let now = date(2026, 10, 18, 9)
        let finish = RecurringBakePlanner.nextFinishDate(lastFinish: lastFinish, duration: 0,
                                                          intervalDays: 5, now: now, calendar: calendar)
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
        let finish = RecurringBakePlanner.nextFinishDate(lastFinish: lastFinish, duration: 18 * 60,
                                                          intervalDays: 5, now: now, calendar: calendar)
        #expect(finish == date(2026, 10, 11, 10))
    }

    @Test("Disabled (intervalDays 0) never produces a date")
    func disabledIntervalReturnsNil() {
        let finish = RecurringBakePlanner.nextFinishDate(lastFinish: date(2026, 10, 1, 10), duration: 0,
                                                         intervalDays: 0, now: date(2026, 10, 1, 10), calendar: calendar)
        #expect(finish == nil)
    }

    @Test("The time of day survives a daylight-saving change")
    func survivesDaylightSavingChange() {
        // Clocks in Europe/Berlin go back on 2026-10-25. Stepping by
        // calendar days instead of fixed 86 400-second multiples keeps the
        // plan at 18:00 local time on both sides of the change.
        let lastFinish = date(2026, 10, 20, 18)
        let now        = date(2026, 10, 20, 19)
        let finish = RecurringBakePlanner.nextFinishDate(lastFinish: lastFinish, duration: 0,
                                                         intervalDays: 7, now: now, calendar: calendar)
        #expect(finish == date(2026, 10, 27, 18))
    }

    // MARK: A starter is fed, not baked

    @Test("A starter's rhythm is measured from the start of its last feeding plus the plan's length")
    func starterFromLastFeeding() {
        let feeding = date(2026, 10, 1, 8)
        let finish = RecurringBakePlanner.rhythmFinish(lastBakeFinish: nil, lastFeedingStart: feeding,
                                                       duration: 720, calendar: calendar)
        #expect(finish == date(2026, 10, 1, 20))
    }

    @Test("An older bake-history entry counts when it is later, so a running rhythm does not jump")
    func laterOfFeedingAndOldEntry() {
        let old = date(2026, 10, 3, 20)
        #expect(RecurringBakePlanner.rhythmFinish(lastBakeFinish: old, lastFeedingStart: date(2026, 10, 1, 8),
                                                  duration: 720, calendar: calendar) == old)
        #expect(RecurringBakePlanner.rhythmFinish(lastBakeFinish: date(2026, 9, 1, 20),
                                                  lastFeedingStart: date(2026, 10, 1, 8),
                                                  duration: 720, calendar: calendar) == date(2026, 10, 1, 20))
        #expect(RecurringBakePlanner.rhythmFinish(lastBakeFinish: old, lastFeedingStart: nil,
                                                  duration: 720, calendar: calendar) == old)
        #expect(RecurringBakePlanner.rhythmFinish(lastBakeFinish: nil, lastFeedingStart: nil,
                                                  duration: 720, calendar: calendar) == nil)
    }
}
