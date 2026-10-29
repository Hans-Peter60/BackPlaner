//
//  RecipeFileFormatTests.swift
//  BackPlanerTests
//
//  The recipe file format on its own, without Core Data: writing a file,
//  reading it back, and refusing what cannot be read. And the units the
//  calculation logic sees once the app has started.
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("The recipe file format")
struct RecipeFileFormatTests {

    private func sample(_ name: String) -> RecipeExportData {
        RecipeExportData(
            name: name, summary: "", urlLink: nil, prepTime: 60, totalWeight: 500,
            tags: ["Weizen"], rating: 0, recurrenceIntervalDays: 0, image: Data([0x01]),
            components: [
                RecipeExportComponent(name: "Teig", number: 1, ingredients: [
                    RecipeExportIngredient(name: "Weizenmehl 550", number: 1, unit: "g",
                                           weight: 300, normWeight: 300, num: 0, denom: 0),
                ]),
            ],
            instructions: [
                RecipeExportInstruction(instruction: "Kneten", step: 1, duration: 10,
                                        startTime: 0, bakeFlag: false, componentName: "Teig"),
            ])
    }

    @Test("A written file reads back as the same recipes")
    func roundTrip() throws {
        let file = RecipeExportFile(recipes: [sample("Brot"), sample("Brötchen")])

        let data = try file.encoded()

        #expect(try RecipeImport.decodeFile(data) == file)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\n"))
        #expect(text.contains("\"formatVersion\" : \(RecipeExportFile.currentFormatVersion)"))
    }

    @Test("Something that is no recipe file is refused as unreadable")
    func unreadable() {
        #expect(throws: RecipeImportError.unreadableFile) {
            try RecipeImport.decodeFile(Data("kein Rezept".utf8))
        }
        #expect(throws: RecipeImportError.unreadableFile) {
            try RecipeImport.decodeFile(Data("{\"recipes\": 3}".utf8))
        }
    }

    @Test("A file from a newer version is refused as such")
    func newerVersion() throws {
        var file = RecipeExportFile(recipes: [sample("Brot")])
        file.formatVersion = RecipeExportFile.currentFormatVersion + 1

        #expect(throws: RecipeImportError.unsupportedFormatVersion) {
            try RecipeImport.decodeFile(try file.encoded())
        }
    }

    @Test("Once the app has started, the logic sees the bundled units and the user's own")
    func unitSetsIncludeCustomUnits() {
        #expect(!GlobalVariables.bundledUnitSets.isEmpty)
        #expect(GlobalVariables.unitSets.count
                == GlobalVariables.bundledUnitSets.count + CustomUnitStore.shared.unitSets.count)
    }
}
