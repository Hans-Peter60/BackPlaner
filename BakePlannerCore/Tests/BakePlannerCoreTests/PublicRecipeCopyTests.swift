//
//  PublicRecipeCopyTests.swift
//  BakePlannerCoreTests
//
//  A public recipe taken over into the own recipes.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("A public recipe taken over")
struct PublicRecipeCopyTests {

    private func instruction(_ text: String, step: Double, duration: Int) -> InstructionFB {
        let instruction = InstructionFB()
        instruction.instruction = text
        instruction.step = step
        instruction.duration = duration
        instruction.startTime = 999
        return instruction
    }

    private func ingredient(_ name: String, number: Int, weight: Double, normWeight: Double) -> IngredientFB {
        let ingredient = IngredientFB()
        ingredient.name = name
        ingredient.number = number
        ingredient.unit = "g"
        ingredient.weight = weight
        ingredient.normWeight = normWeight
        return ingredient
    }

    private func recipe() -> RecipeFB {
        let recipe = RecipeFB()
        recipe.id = "doc"
        recipe.name = "Landbrot"
        recipe.summary = "Kräftig"
        recipe.tags = ["Roggen"]
        recipe.prepTime = 5
        recipe.totalWeight = 1
        let component = ComponentFB()
        component.name = "Hauptteig"
        component.number = 1
        // The stored normalised weight is stale; grams count as written.
        component.ingredients = [ingredient("Mehl", number: 1, weight: 500, normWeight: 400),
                                 ingredient("Wasser", number: 2, weight: 350, normWeight: 350)]
        recipe.components = [component]
        recipe.instructions = [instruction("Backen", step: 2, duration: 60),
                               instruction("Kneten", step: 1, duration: 30),
                               instruction(GlobalVariables.bakeEnd, step: 3, duration: 0)]
        return recipe
    }

    @Test("Start times and duration are worked out again from the steps")
    func times() {
        let content = PublicRecipeCopy.content(of: recipe(), imageData: nil)
        #expect(content.instructions.map(\.instruction) == ["Kneten", "Backen"])
        #expect(content.instructions.map(\.startTime) == [0, 30])
        #expect(content.prepTime == 90)
    }

    @Test("The weights in grams and the total are worked out again")
    func weights() {
        let content = PublicRecipeCopy.content(of: recipe(), imageData: Data([7]))
        #expect(content.components.first?.ingredients.map(\.normWeight) == [500, 350])
        #expect(content.totalWeight == 850)
        #expect(content.name == "Landbrot")
        #expect(content.summary == "Kräftig")
        #expect(content.tags == ["Roggen"])
        #expect(content.image == Data([7]))
        #expect(content.recurrenceIntervalDays == 0)
    }
}
