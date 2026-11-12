//
//  PantryBackupTests.swift
//  BackPlanerTests
//
//  The pantry travelling in the backup file through the app's Core Data
//  stores: written with the full backup, read onto the items the pantry
//  does not have yet.
//

import BakePlannerCore
import CoreData
import Foundation
import Testing
@testable import BackPlaner

@Suite("Pantry in the backup file, through Core Data")
@MainActor
struct PantryBackupTests {

    @Test("A file with a pantry fills the pantry on import; known names stay as they are")
    func importFillsPantry() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let pantry = CoreDataPantryStore(context: context)
        _ = try pantry.add(name: "Hefe", amount: 42, unit: .gram, bestBefore: nil, note: "")

        let file = RecipeExportFile(recipes: [RecipeStoreContract.bread()], pantry: [
            RecipeExportPantryItem(name: "Roggenmehl 1150", amount: 1, unit: "kg", note: "angebrochen"),
            RecipeExportPantryItem(name: "hefe", amount: 1, unit: "St"),
        ])
        #expect(file.formatVersion == 7)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pantry-backup-\(UUID().uuidString).json")
        try file.encoded().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try RecipeImport.importRecipes(from: url, into: context)
        #expect(result == RecipeImportResult(recipes: 1, pantryItems: 1))
        let items = try pantry.items()
        #expect(items.map(\.name) == ["Hefe", "Roggenmehl 1150"])
        #expect(items[0].amount == 42 && items[0].unit == .gram)
        #expect(items[1].amount == 1 && items[1].unit == .kilogram && items[1].note == "angebrochen")
    }

    @Test("The full backup through the app's Core Data stores carries the pantry, the shared recipe's file does not")
    func exportCarriesPantry() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let pantry = CoreDataPantryStore(context: context)
        let item = try pantry.add(name: "Testmehl", amount: 500, unit: .gram, bestBefore: nil, note: "")

        let full = try RecipeExportFile(recipeIDs: [], from: CoreDataRecipeStore(context: context),
                                        bakeHistory: CoreDataBakeHistoryStore(context: context),
                                        starterFeedings: CoreDataStarterFeedingLogStore(context: context),
                                        pantry: pantry)
        #expect(full.pantry == [RecipeExportPantryItem(name: item.name, amount: 500, unit: "g")])
        #expect(full.formatVersion == 7)
        let shared = try RecipeExportFile(recipeIDs: [], from: CoreDataRecipeStore(context: context))
        #expect(shared.pantry == nil && shared.formatVersion == 1)
    }
}
