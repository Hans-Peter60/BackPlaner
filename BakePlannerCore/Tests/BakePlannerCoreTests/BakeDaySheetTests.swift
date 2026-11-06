//
//  BakeDaySheetTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("The Backtag-Zettel: the plans' steps day by day")
struct BakeDaySheetTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()
    private let german = Locale(identifier: "de_DE")

    private func time(_ hour: Int, _ minute: Int = 0, day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func step(_ instruction: String, recipe: String, at date: Date, duration: Int, number: Double = 1) -> ScheduledStepData {
        ScheduledStepData(id: UUID(), planID: nil, recipeName: recipe, instruction: instruction, step: number,
                          startTime: 0, duration: duration, date: date, isAutomaticRecurrence: false, servingScale: 1)
    }

    @Test("Steps of two plans are sorted by time and grouped by day, with the ingredients a step mixes")
    func groupedByDay() {
        let steps = [
            step("Bei 250 °C backen", recipe: "Landbrot", at: time(7, 5, day: 7), duration: 45, number: 3),
            step("Sauerteig ansetzen", recipe: "Landbrot", at: time(18, day: 6), duration: 720),
            step("Hauptteig kneten", recipe: "Landbrot", at: time(6, day: 7), duration: 10, number: 2),
            step("Backende", recipe: "Zopf", at: time(9, 30, day: 7), duration: 0, number: 99),
        ]
        let sheet = BakeDaySheet(steps: steps, ingredients: { step in
            step.instruction == "Hauptteig kneten" ? ("Hauptteig", ["• 500 g Weizenmehl 550", "• 350 g Wasser"]) : nil
        }, locale: german, calendar: calendar, now: time(17, 30, day: 6))

        #expect(sheet.title == "Backtag-Zettel")
        #expect(sheet.subtitle.hasPrefix("Stand: ") && sheet.subtitle.hasSuffix("17:30") && sheet.subtitle.contains("2026"))
        #expect(sheet.days.map(\.title) == ["Freitag, 6. November 2026", "Samstag, 7. November 2026"])
        #expect(sheet.days[0].rows.map(\.instruction) == ["Sauerteig ansetzen"])
        #expect(sheet.days[1].rows.map(\.time) == ["06:00", "07:05", "09:30"])
        #expect(sheet.days[1].rows.map(\.recipeName) == ["Landbrot", "Landbrot", "Zopf"])
        #expect(sheet.days[1].rows[0].componentName == "Hauptteig")
        #expect(sheet.days[1].rows[0].ingredientLines.count == 2)
        #expect(sheet.days[1].rows[0].duration == "10m")
        #expect(sheet.days[1].rows[2].duration == "")
    }

    @Test("Without steps there are no days")
    func empty() {
        let sheet = BakeDaySheet(steps: [], ingredients: { _ in nil }, locale: german, calendar: calendar)
        #expect(sheet.days.isEmpty)
    }
}
