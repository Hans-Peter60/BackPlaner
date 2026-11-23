//
//  RecipeExportTests.swift
//  BackPlanerTests
//

import BakePlannerCore
import Foundation
import Testing
@testable import BackPlaner

@Suite("Recipe export file: encoding, decoding, and the import guards")
struct RecipeExportTests {

    private func sampleRecipe() -> RecipeExportData {
        RecipeExportData(
            name: "Landbrot",
            summary: "Rustikales Mischbrot",
            urlLink: "https://example.com/landbrot",
            prepTime: 180,
            totalWeight: 1200,
            tags: ["Mischbrot", "Sauerteig"],
            rating: 4,
            recurrenceIntervalDays: 0,
            image: Data([0x01, 0x02, 0x03]),
            components: [
                RecipeExportComponent(name: "Hauptteig", number: 0, ingredients: [
                    RecipeExportIngredient(name: "Weizenmehl 550", number: 0, unit: "g", weight: 500, normWeight: 500, num: 0, denom: 0),
                    RecipeExportIngredient(name: "Wasser", number: 1, unit: "g", weight: 340, normWeight: 340, num: 0, denom: 0)
                ])
            ],
            instructions: [
                RecipeExportInstruction(instruction: "Mehl und Wasser verkneten", step: 1, duration: 10, startTime: 0, bakeFlag: false, componentName: "Hauptteig")
            ]
        )
    }

    @Test("A recipe survives encoding and decoding unchanged")
    func roundTrip() throws {
        let file = RecipeExportFile(recipes: [sampleRecipe()])

        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(RecipeExportFile.self, from: data)

        #expect(decoded == file)
    }

    @Test("A recipe without an image round-trips with no image, not an empty one")
    func roundTripWithoutImage() throws {
        var recipe = sampleRecipe()
        recipe.image = nil
        let file = RecipeExportFile(recipes: [recipe])

        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(RecipeExportFile.self, from: data)

        #expect(decoded.recipes.first?.image == nil)
    }

    @Test("Several recipes in one file all survive the round trip")
    func multipleRecipes() throws {
        var second = sampleRecipe()
        second.name = "Baguette"
        let file = RecipeExportFile(recipes: [sampleRecipe(), second])

        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(RecipeExportFile.self, from: data)

        #expect(decoded.recipes.map(\.name) == ["Landbrot", "Baguette"])
    }

    @Test("Only a format version up to the app's own is accepted")
    func formatVersionGuard() {
        #expect(RecipeExportFile.isSupported(formatVersion: RecipeExportFile.currentFormatVersion))
        #expect(RecipeExportFile.isSupported(formatVersion: RecipeExportFile.currentFormatVersion - 1))
        #expect(!RecipeExportFile.isSupported(formatVersion: RecipeExportFile.currentFormatVersion + 1))
    }

    @Test("Garbage data does not decode as a recipe file")
    func garbageDataFailsToDecode() {
        let garbage = Data("not json".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RecipeExportFile.self, from: garbage)
        }
    }
}
