//
//  PlannedStepSourceTests.swift
//  BakePlannerCoreTests
//
//  A public recipe and the user's own copy share a name; a planned step
//  must lead back to the one it was planned from.
//

import Testing
@testable import BakePlannerCore

@Suite("Which recipe a planned step came from")
struct PlannedStepSourceTests {

    private let publicSteps = [
        PlannedStepSource.Step(step: 3, instruction: "Hauptteig: Zunächst das heiße Wasser mit den Kartoffeln mischen."),
    ]
    /// An older copy, the step still split in two.
    private let ownSteps = [
        PlannedStepSource.Step(step: 3.1, instruction: "Zunächst das heiße Wasser mit den Kartoffeln mischen."),
        PlannedStepSource.Step(step: 3.2, instruction: "Dann alle weiteren Zutaten in die Schüssel wiegen."),
    ]

    @Test("A step planned from the public recipe finds the public recipe, however the copy reads")
    func publicPlan() {
        #expect(PlannedStepSource.source(ofStep: 3, instruction: publicSteps[0].instruction,
                                         publicSteps: publicSteps, ownSteps: ownSteps) == .publicRecipe)
    }

    @Test("A step only the own copy has was planned from the copy")
    func ownPlan() {
        #expect(PlannedStepSource.source(ofStep: 3.1, instruction: ownSteps[0].instruction,
                                         publicSteps: publicSteps, ownSteps: ownSteps) == .ownRecipe)
    }

    @Test("A step both read alike, or a step the plan added, goes to the public recipe")
    func ties() {
        #expect(PlannedStepSource.source(ofStep: 3, instruction: publicSteps[0].instruction,
                                         publicSteps: publicSteps, ownSteps: publicSteps) == .publicRecipe)
        #expect(PlannedStepSource.source(ofStep: 0, instruction: "Backofen anstellen",
                                         publicSteps: publicSteps, ownSteps: ownSteps) == .publicRecipe)
    }

    @Test("With only one of the two, that one")
    func onlyOne() {
        #expect(PlannedStepSource.source(ofStep: 3, instruction: "x", publicSteps: nil, ownSteps: ownSteps) == .ownRecipe)
        #expect(PlannedStepSource.source(ofStep: 3, instruction: "x", publicSteps: publicSteps, ownSteps: nil) == .publicRecipe)
        #expect(PlannedStepSource.source(ofStep: 3, instruction: "x", publicSteps: nil, ownSteps: nil) == nil)
    }
}
