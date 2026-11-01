//
//  CloudRecipeImportTests.swift
//  BakePlannerCoreTests
//
//  The cloud AI's answer, read as the Android SDK hands it out.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("The cloud AI's recipe")
struct CloudRecipeImportTests {

    private let response: [String: Any] = [
        "model": "gemini",
        "recipe": [
            "title": "Roggenbrot",
            "summary": "Kräftig",
            "sourceLanguage": "de",
            "preparationMinutes": Int64(720),
            "components": [
                ["name": "Sauerteig", "ingredients": [
                    ["name": "Roggenmehl", "amount": Int64(100), "unit": "g"],
                    ["name": "Wasser", "amount": 100.0, "unit": "g"],
                ] as [Any]] as [String: Any],
                ["name": "Hauptteig", "ingredients": [
                    ["name": "Roggenmehl", "amount": 400.0, "unit": "g"],
                ] as [Any]] as [String: Any],
            ] as [Any],
            "instructions": [
                ["text": "Sauerteig mischen", "durationMinutes": Int64(720), "componentName": "Sauerteig", "isBaking": false] as [String: Any],
                ["text": "60 Minuten backen", "durationMinutes": Int64(60), "componentName": "", "isBaking": true] as [String: Any],
            ] as [Any],
            "warnings": ["Menge geschätzt"],
        ] as [String: Any],
    ]

    @Test("Numbers come as Long or Double, as the Android SDK delivers them")
    func readsResponse() throws {
        let analysis = try #require(CloudRecipeAnalysis(response: response))
        #expect(analysis.model == "gemini")
        #expect(analysis.recipe.title == "Roggenbrot")
        #expect(analysis.recipe.preparationMinutes == 720)
        #expect(analysis.recipe.components.map(\.name) == ["Sauerteig", "Hauptteig"])
        #expect(analysis.recipe.components[0].ingredients.map(\.amount) == [100, 100])
        #expect(analysis.recipe.instructions.map(\.durationMinutes) == [720, 60])
        #expect(analysis.recipe.instructions[1].isBaking)
        #expect(analysis.recipe.warnings == ["Menge geschätzt"])
    }

    @Test("An answer without a recipe is none")
    func rejectsOtherAnswers() {
        #expect(CloudRecipeAnalysis(response: ["model": "gemini"]) == nil)
        #expect(CloudRecipeAnalysis(response: "text") == nil)
    }

    @MainActor
    @Test("The recipe built from it has components, steps and weight")
    func makesRecipe() throws {
        let recipe = try #require(CloudRecipeAnalysis(response: response)).recipe.makeRecipe()
        #expect(recipe.name == "Roggenbrot")
        #expect(recipe.components.count == 2)
        #expect(recipe.totalWeight == 600)
        #expect(recipe.instructions.first?.instruction == "Sauerteig: Sauerteig mischen" || recipe.instructions.first?.instruction == "Sauerteig mischen")
        #expect(recipe.instructions.last?.bakeFlag == true)
        #expect(RecipeImportCheck.hasRecipeData(recipe))
        recipe.instructions = []
        #expect(!RecipeImportCheck.hasRecipeData(recipe))
    }
}
