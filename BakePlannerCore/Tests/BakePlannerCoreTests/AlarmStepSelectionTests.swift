//
//  AlarmStepSelectionTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Which scheduled steps ring as an alarm")
struct AlarmStepSelectionTests {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let loafPlan = UUID()
    private let starterPlan = UUID()

    private func step(_ instruction: String, number: Double, minutes: Int, plan: UUID, recipe: String = "Brot") -> ScheduledStepData {
        ScheduledStepData(id: UUID(), planID: plan, recipeName: recipe, instruction: instruction, step: number,
                          startTime: 0, duration: 0, date: now.addingTimeInterval(TimeInterval(minutes * 60)),
                          isAutomaticRecurrence: false, servingScale: 1)
    }

    private var steps: [ScheduledStepData] {
        [
            step("Teig kneten", number: 1, minutes: -30, plan: loafPlan),
            step("Teig gehen lassen", number: 2, minutes: 10, plan: loafPlan),
            step("Backofen anstellen (250 °C)", number: 2.9, minutes: 60, plan: loafPlan),
            step("Bei 250 °C 45 Minuten backen", number: 3, minutes: 75, plan: loafPlan),
            step("Backende", number: 99, minutes: 120, plan: loafPlan),
            step("Anstellgut füttern", number: 1, minutes: 20, plan: starterPlan, recipe: "Roggensauer"),
            step("Fütterung abgeschlossen", number: 99, minutes: 500, plan: starterPlan, recipe: "Roggensauer"),
        ]
    }

    @Test("Off rings nothing")
    func off() {
        #expect(AlarmStepSelection.steps(for: .off, in: steps, now: now).isEmpty)
    }

    @Test("Oven steps: oven on, into the oven and the end — of a plan that bakes, and only ahead of now")
    func ovenSteps() {
        let found = AlarmStepSelection.steps(for: .oven, in: steps, now: now)
        #expect(found.map(\.instruction) == ["Backofen anstellen (250 °C)", "Bei 250 °C 45 Minuten backen", "Backende"])
    }

    @Test("All steps ahead of now, the starter's included; the one already due is left out")
    func allSteps() {
        let found = AlarmStepSelection.steps(for: .all, in: steps, now: now)
        #expect(found.count == 6)
        #expect(!found.contains { $0.instruction == "Teig kneten" })
    }

    @Test("A recipe's own preheating step counts as the oven going on")
    func explicitPreheat() {
        let plan = UUID()
        let own = [
            step("Backofen auf 230 °C vorheizen", number: 4, minutes: 30, plan: plan),
            step("Brot einschießen und backen", number: 5, minutes: 50, plan: plan),
            step("Backende", number: 99, minutes: 100, plan: plan),
        ]
        #expect(AlarmStepSelection.steps(for: .oven, in: own, now: now).count == 3)
    }

    @Test("Without a plan id the recipe name groups the steps")
    func withoutPlanID() {
        var old = steps.filter { $0.planID == loafPlan }
        for index in old.indices { old[index].planID = nil }
        #expect(AlarmStepSelection.steps(for: .oven, in: old, now: now).count == 3)
    }
}
