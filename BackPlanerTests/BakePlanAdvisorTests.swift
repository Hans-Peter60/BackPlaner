//
//  BakePlanAdvisorTests.swift
//  BackPlanerTests
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("Dates at which no step of a plan falls into the night")
struct BakePlanAdvisorTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    /// Saturday 10 October 2026, or the Friday before with `day: 9`.
    private func time(_ hour: Int, _ minute: Int = 0, day: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private let anyDate = Date.distantPast...Date.distantFuture

    /// Knead, rise, bake, cool: 2 h 20 min, with the oven switched on at 55.
    private let loaf = [
        PlanStep(instruction: "Teig kneten", step: 1, startTime: 0, duration: 10),
        PlanStep(instruction: "Teig gehen lassen", step: 2, startTime: 10, duration: 60),
        PlanStep(instruction: "Bei 250 °C backen", step: 3, startTime: 70, duration: 40),
        PlanStep(instruction: "Auskühlen lassen", step: 4, startTime: 110, duration: 30),
    ]

    /// A sourdough set the evening before: 15 h 10 min in all.
    private let sourdoughLoaf = [
        PlanStep(instruction: "Sauerteig ansetzen und reifen lassen", step: 1, startTime: 0, duration: 720),
        PlanStep(instruction: "Hauptteig kneten", step: 2, startTime: 720, duration: 20),
        PlanStep(instruction: "Stückgare", step: 3, startTime: 740, duration: 120),
        PlanStep(instruction: "Bei 240 °C backen", step: 4, startTime: 860, duration: 50),
    ]

    private func plan(_ steps: [PlanStep], prepTime: Int, anchor: PlanAnchor, at date: Date) -> BakePlan {
        BakePlan(recipeName: "Brot", steps: steps, prepTime: prepTime, anchor: anchor,
                 date: date, languageCode: "de", preheatTime: 15, calendar: calendar)
    }

    private func suggestions(for plan: BakePlan,
                             allowed: ClosedRange<Date>? = nil,
                             existing: [BakeWindow] = []) -> [NightFreeDate] {
        BakePlanAdvisor.nightFreeDates(for: plan, dayStart: 6, dayEnd: 22,
                                       allowedDates: allowed ?? anyDate,
                                       existingWindows: existing, ovenCount: 1)
    }

    @Test("A plan inside the day gets no suggestion")
    func nothingToSuggestForADayPlan() {
        #expect(suggestions(for: plan(loaf, prepTime: 140, anchor: .startsAt, at: time(9))).isEmpty)
    }

    @Test("Starting at 04:30: 06:00 the same morning first, then 19:30 the evening before")
    func startingTooEarly() throws {
        let found = suggestions(for: plan(loaf, prepTime: 140, anchor: .startsAt, at: time(4, 30)))
        #expect(found.map(\.date) == [time(6), time(19, 30, day: 9)])
        #expect(found.map(\.shift) == [90, -540])

        let morning = try #require(found.first)
        #expect(morning.start == time(6))
        #expect(morning.finish == time(8, 20))
    }

    @Test("Finishing by 08:00 kneads at 04:50; finishing by 09:15 kneads at 06:05")
    func finishingTooEarly() throws {
        let found = suggestions(for: plan(sourdoughLoaf, prepTime: 910, anchor: .finishesBy, at: time(8)))
        let later = try #require(found.first)
        #expect(later.date == time(9, 15))
        #expect(later.shift == 75)
        // The sourdough is then set at 18:05 the evening before.
        #expect(later.start == time(18, 5, day: 9))
        #expect(later.finish == time(9, 15))

        // Earlier only works if the whole plan fits into the day before:
        // sourdough at 06:50, finished at 22:00 sharp, which still counts.
        let earlier = try #require(found.last)
        #expect(earlier.date == time(22, day: 9))
        #expect(earlier.shift == -600)
    }

    @Test("A suggestion never starts the plan before the picker allows")
    func staysInsideTheAllowedRange() {
        let found = suggestions(for: plan(loaf, prepTime: 140, anchor: .startsAt, at: time(4, 30)),
                                allowed: time(4, 30)...time(23, 59, day: 31))
        #expect(found.map(\.date) == [time(6)])
    }

    @Test("A date at which the bake would need a second oven is skipped")
    func skipsDatesThatNeedAnotherOven() {
        let zopf = BakeWindow(recipeName: "Zopf", start: time(7), end: time(8, 30))
        let found = suggestions(for: plan(loaf, prepTime: 140, anchor: .startsAt, at: time(4, 30)),
                                existing: [zopf])
        // 06:00 would bake 07:10–08:20, right inside the Zopf. From 07:30 the
        // bake begins at 08:40, after it.
        #expect(found.first?.date == time(7, 30))
    }

    @Test("The day window counts the edges as inside")
    func dayWindowEdges() {
        #expect(!BakePlanValidator.isOutsideDay(time(6), dayStart: 6, dayEnd: 22, calendar: calendar))
        #expect(!BakePlanValidator.isOutsideDay(time(22), dayStart: 6, dayEnd: 22, calendar: calendar))
        #expect(BakePlanValidator.isOutsideDay(time(5, 59), dayStart: 6, dayEnd: 22, calendar: calendar))
        #expect(BakePlanValidator.isOutsideDay(time(22, 1), dayStart: 6, dayEnd: 22, calendar: calendar))
    }
}
