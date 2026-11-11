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

    @Test("The free imports come along when the server sends them, as Long too")
    func readsFreeImports() throws {
        #expect(try #require(CloudRecipeAnalysis(response: response)).freeImports == nil)
        var withAllowance = response
        withAllowance["freeImports"] = ["used": Int64(3), "limit": Int64(5)] as [String: Any]
        let analysis = try #require(CloudRecipeAnalysis(response: withAllowance))
        #expect(analysis.freeImports == CloudRecipeAnalysis.FreeImports(used: 3, limit: 5))
        #expect(analysis.freeImports?.remaining == 2)

        let decoded = try JSONDecoder().decode(CloudRecipeAnalysis.self, from: Data("""
            {"recipe": {"title": "Brot", "summary": "", "sourceLanguage": "de", "preparationMinutes": 10,
                        "components": [], "instructions": [], "warnings": []},
             "model": "gemini", "freeImports": {"used": 5, "limit": 5}}
            """.utf8))
        #expect(decoded.freeImports?.remaining == 0)
    }

    @Test("The notice names the last two free imports and the last one, and says nothing before")
    func freeImportsNotice() {
        typealias Imports = CloudRecipeAnalysis.FreeImports
        let german = Locale(identifier: "de_DE")
        #expect(Imports(used: 1, limit: 5).notice(locale: german) == nil)
        #expect(Imports(used: 3, limit: 5).notice(locale: german) == "Noch 2 kostenlose Cloud-Importe in diesem Monat.")
        #expect(Imports(used: 4, limit: 5).notice(locale: german) == "Noch ein kostenloser Cloud-Import in diesem Monat.")
        #expect(Imports(used: 5, limit: 5).notice(locale: german)?.hasPrefix("Das war der letzte kostenlose Cloud-Import") == true)
        #expect(Imports(used: 7, limit: 5).notice(locale: german)?.hasPrefix("Das war der letzte") == true)
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
