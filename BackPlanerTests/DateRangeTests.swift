//
//  DateRangeTests.swift
//  BackPlanerTests
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("Date ranges offered by the date pickers")
struct DateRangeTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test("Planning runs from the start of today to the same day next year")
    func planningSpansOneYearFromMidnight() {
        let range = GlobalVariables.dateRange(to: DateComponents(year: 1),
                                              around: date(2026, 10, 5, 14, 30),
                                              calendar: calendar)
        #expect(range.lowerBound == date(2026, 10, 5))
        #expect(range.upperBound == date(2027, 10, 5))
    }

    @Test("A range asked for after midnight starts on the new day")
    func followsTheCurrentDay() {
        let evening = GlobalVariables.dateRange(to: DateComponents(year: 1),
                                                around: date(2026, 10, 5, 23, 59),
                                                calendar: calendar)
        let morning = GlobalVariables.dateRange(to: DateComponents(year: 1),
                                                around: date(2026, 10, 6, 0, 1),
                                                calendar: calendar)
        #expect(evening.lowerBound == date(2026, 10, 5))
        #expect(morning.lowerBound == date(2026, 10, 6))
    }

    @Test("The bake history reaches ten years back and one month ahead")
    func historySpan() {
        let range = GlobalVariables.dateRange(from: DateComponents(year: -10),
                                              to: DateComponents(month: 1),
                                              around: date(2026, 12, 15, 9),
                                              calendar: calendar)
        #expect(range.lowerBound == date(2016, 12, 15))
        #expect(range.upperBound == date(2027, 1, 15))
    }

    @Test("Month and leap-day edges resolve instead of trapping")
    func calendarEdges() {
        let endOfJanuary = GlobalVariables.dateRange(to: DateComponents(month: 1),
                                                     around: date(2026, 1, 31, 12),
                                                     calendar: calendar)
        #expect(endOfJanuary.upperBound == date(2026, 2, 28))

        let leapDay = GlobalVariables.dateRange(to: DateComponents(year: 1),
                                                around: date(2028, 2, 29, 12),
                                                calendar: calendar)
        #expect(leapDay.upperBound == date(2029, 2, 28))
    }

    @Test("Offsets given in reverse still yield an ordered range")
    func reversedOffsets() {
        let range = GlobalVariables.dateRange(from: DateComponents(month: 1),
                                              to: DateComponents(),
                                              around: date(2026, 10, 5, 8),
                                              calendar: calendar)
        #expect(range.lowerBound == date(2026, 10, 5))
        #expect(range.upperBound == date(2026, 11, 5))
    }
}
