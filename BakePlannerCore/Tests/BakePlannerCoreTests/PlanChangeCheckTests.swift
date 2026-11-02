//
//  PlanChangeCheckTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("A plan notices when its recipe was changed after planning")
struct PlanChangeCheckTests {

    private let instructions = [
        RecipeExportInstruction(instruction: "Kneten", step: 1, duration: 10, startTime: 0, bakeFlag: false),
        RecipeExportInstruction(instruction: "Gehen lassen", step: 2, duration: 60, startTime: 10, bakeFlag: false),
        RecipeExportInstruction(instruction: "Backen", step: 3, duration: 40, startTime: 70, bakeFlag: true),
    ]

    private func planned(_ step: Double, _ text: String, _ minutes: Int) -> PlanChangeCheck.PlannedStep {
        PlanChangeCheck.PlannedStep(step: step, instruction: text, duration: minutes)
    }

    @Test("Unchanged steps, with the generated oven and finish steps, are no change")
    func unchanged() {
        let plan = [planned(1, "Kneten", 10), planned(2, "Gehen lassen", 60),
                    planned(2.9, "Backofen anstellen (250 °C)", 15), planned(3, "Backen", 40),
                    planned(3.1, "Backofen auf 220 °C zurückdrehen", 0),
                    planned(99, "Backvorgang ist beendet", 0)]
        #expect(!PlanChangeCheck.recipeChanged(instructions: instructions, plannedSteps: plan))
    }

    @Test("A step done and gone from the plan is no change")
    func doneStep() {
        #expect(!PlanChangeCheck.recipeChanged(instructions: instructions,
                                               plannedSteps: [planned(2, "Gehen lassen", 60), planned(3, "Backen", 40)]))
    }

    @Test("An edited duration, an edited text or a removed step is a change")
    func changed() {
        #expect(PlanChangeCheck.recipeChanged(instructions: instructions, plannedSteps: [planned(2, "Gehen lassen", 90)]))
        #expect(PlanChangeCheck.recipeChanged(instructions: instructions, plannedSteps: [planned(2, "Stockgare", 60)]))
        #expect(PlanChangeCheck.recipeChanged(instructions: instructions, plannedSteps: [planned(4, "Auskühlen", 30)]))
    }
}
