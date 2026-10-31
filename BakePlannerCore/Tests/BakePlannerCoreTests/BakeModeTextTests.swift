//
//  BakeModeTextTests.swift
//  BakePlannerCoreTests
//
//  What the bake mode shows and reads aloud for a planned step.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Bake mode: ingredients and spoken text of a step")
struct BakeModeTextTests {

    private func step(_ number: Double, _ instruction: String, scale: Double) -> ScheduledStepData {
        ScheduledStepData(id: UUID(), planID: UUID(), recipeName: "Landbrot", instruction: instruction, step: number,
                          startTime: 0, duration: 0, date: Date(timeIntervalSince1970: 1_800_000_000),
                          isAutomaticRecurrence: false, servingScale: scale)
    }

    @Test("A step that mixes a component shows its ingredients at the planned amount")
    func ingredientsAtScale() throws {
        let bread = RecipeStoreContract.bread()
        let kneading = step(2, "Alle Zutaten kneten", scale: 2)
        let component = try #require(BakeModeText.component(of: kneading, in: bread))
        #expect(component.name == "Hauptteig")

        let lines = BakeModeText.ingredientLines(of: component, scale: kneading.effectiveServingScale)
        #expect(lines.count == component.ingredients.count)
        #expect(lines.allSatisfy { $0.hasPrefix("• ") })
        let flour = try #require(lines.first { $0.hasSuffix("Weizenmehl 550") })
        #expect(flour.contains("800"))
    }

    @Test("The spoken text is the step, then the ingredients as sentences, without bullets")
    func spoken() throws {
        let bread = RecipeStoreContract.bread()
        let kneading = step(2, "Alle Zutaten\nkneten", scale: 1)
        let component = try #require(BakeModeText.component(of: kneading, in: bread))

        let text = BakeModeText.spokenText(instruction: kneading.instruction, component: component, scale: 1)
        #expect(text.hasPrefix("Alle Zutaten. kneten"))
        #expect(text.contains("Hauptteig"))
        #expect(text.contains("Weizenmehl 550"))
        #expect(!text.contains("•"))

        #expect(BakeModeText.spokenText(instruction: "Falten", component: nil, scale: 1) == "Falten")
    }

    @Test("Steps planned before the scale was recorded show the recipe as stored")
    func effectiveScale() {
        #expect(step(1, "Kneten", scale: 0).effectiveServingScale == 1)
        #expect(step(1, "Kneten", scale: 1.5).effectiveServingScale == 1.5)
    }
}
