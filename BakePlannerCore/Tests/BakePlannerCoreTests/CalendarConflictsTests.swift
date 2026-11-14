//
//  CalendarConflictsTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Calendar conflicts of a plan")
struct CalendarConflictsTests {

    private let calendar = Calendar(identifier: .gregorian)
    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: hour, minute: minute))!
    }

    /// Knead 8:00, rest until 10:00, shape 10:00, proof until 11:00, bake 11:00–11:50.
    private var plan: BakePlan {
        let steps = [
            PlanStep(instruction: "Teig kneten", step: 1, startTime: 0, duration: 15),
            PlanStep(instruction: "Stockgare", step: 2, startTime: 15, duration: 105),
            PlanStep(instruction: "Teig formen", step: 3, startTime: 120, duration: 15),
            PlanStep(instruction: "Stückgare", step: 4, startTime: 135, duration: 45),
            PlanStep(instruction: "Bei 250 °C backen", step: 5, startTime: 180, duration: 50),
        ]
        return BakePlan(recipeName: "Test", steps: steps, prepTime: 230, anchor: .startsAt, date: time(8),
                        languageCode: "de", preheatTime: 15, stonePreheatTime: 45, calendar: calendar, ovenProfile: nil)
    }

    @Test("The plan needs the baker for the work, the oven going on, and the bake's start and end")
    func presence() {
        let intervals = CalendarConflicts.presenceIntervals(of: plan)
        #expect(intervals.map(\.interval.start) == [time(8), time(10), time(10, 45), time(11), time(11, 40)])
        #expect(intervals.map(\.step).first == "Teig kneten")
        #expect(intervals[2].step.hasPrefix("Backofen anstellen"))
        #expect(intervals[0].interval.duration == 15 * 60)
    }

    @Test("An appointment during the shaping is a conflict, one during the rest is not, an all-day event never")
    func conflicts() {
        let dentist = CalendarEvent(title: "Zahnarzt", start: time(9, 30), end: time(10, 10))
        let lunch = CalendarEvent(title: "Mittag", start: time(12), end: time(13))
        let holiday = CalendarEvent(title: "Feiertag", start: time(0), end: time(23, 59), isAllDay: true)
        let found = CalendarConflicts.find(in: plan, events: [dentist, lunch, holiday])
        #expect(found.count == 1)
        #expect(found.first?.step == "Teig formen")
        #expect(found.first?.event == dentist)
        #expect(found.first?.stepDate == time(10))
    }

    @Test("A long appointment over the whole bake is reported once per moment it blocks")
    func longAppointment() {
        let meeting = CalendarEvent(title: "Besprechung", start: time(10, 30), end: time(12))
        let found = CalendarConflicts.find(in: plan, events: [meeting])
        #expect(found.map(\.step) == [found[0].step, "Bei 250 °C backen", "Bei 250 °C backen"])
        #expect(found[0].step.hasPrefix("Backofen anstellen"))
    }
}
