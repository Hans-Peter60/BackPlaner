//
//  PlanCalendarEntryTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("A plan's steps as calendar entries")
struct PlanCalendarEntryTests {

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func step(_ instruction: String, minutes: Int, duration: Int, number: Double = 1) -> ScheduledStepData {
        ScheduledStepData(id: UUID(), planID: nil, recipeName: "Landbrot", instruction: instruction, step: number,
                          startTime: minutes, duration: duration, date: start.addingTimeInterval(TimeInterval(minutes * 60)),
                          isAutomaticRecurrence: false, servingScale: 1)
    }

    @Test("One entry per step, in order of time, titled with the recipe, as long as the step takes")
    func entries() {
        let entries = PlanCalendarEntry.entries(for: [
            step("Bei 250 °C backen", minutes: 120, duration: 45, number: 3),
            step("Teig kneten", minutes: 0, duration: 10),
            step("Backende", minutes: 165, duration: 0, number: 99),
        ])
        #expect(entries.map(\.title) == ["Landbrot: Teig kneten", "Landbrot: Bei 250 °C backen", "Landbrot: Backende"])
        #expect(entries[0].start == start)
        // Ten minutes of kneading still take a quarter of an hour in the calendar.
        #expect(entries[0].end == start.addingTimeInterval(15 * 60))
        #expect(entries[1].end == entries[1].start.addingTimeInterval(45 * 60))
        #expect(entries[2].end == entries[2].start.addingTimeInterval(15 * 60))
        #expect(entries.allSatisfy { $0.notes == "Geplant mit BakePlanner." })
    }
}
