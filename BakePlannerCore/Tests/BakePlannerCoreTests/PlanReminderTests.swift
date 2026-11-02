//
//  PlanReminderTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("A reminder's identifier and the step behind it")
struct PlanReminderTests {

    @Test("The identifier names the step, and reads back to it")
    func identifierRoundTrip() {
        let id = UUID()
        let step = ScheduledStepData(id: id, planID: nil, recipeName: "Brot", instruction: "Kneten", step: 1,
                                     startTime: 0, duration: 10, date: Date(), isAutomaticRecurrence: false,
                                     servingScale: 1)
        let identifier = PlanReminder.identifier(of: step)
        #expect(identifier == "bakeplanner-step-" + id.uuidString)
        #expect(PlanReminder.stepID(of: identifier ?? "") == id)
    }

    @Test("Other identifiers belong to no step")
    func foreignIdentifiers() {
        #expect(PlanReminder.stepID(of: "Postponement-123") == nil)
        #expect(PlanReminder.stepID(of: "bakeplanner-step-not-a-uuid") == nil)
    }
}
