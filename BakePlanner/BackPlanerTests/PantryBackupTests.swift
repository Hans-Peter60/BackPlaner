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

@Suite("Imports through Core Data: all or nothing")
@MainActor
struct AtomicImportTests {

    struct Stop: Error {}

    @Test("A failure half-way leaves the store as it was")
    func failureKeepsNothing() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        _ = try CoreDataRecipeStore(context: context).add(contentsOf: [RecipeStoreContract.bread()])

        #expect(throws: Stop.self) {
            try RecipeImport.atomically(in: context) { scratch in
                var zopf = RecipeStoreContract.bread()
                zopf.name = "Zopf"
                _ = try CoreDataRecipeStore(context: scratch).add(contentsOf: [zopf])
                _ = try CoreDataPantryStore(context: scratch).add(name: "Hefe", amount: 42, unit: .gram,
                                                                   bestBefore: nil, note: "")
                throw Stop()
            }
        }
        #expect(try CoreDataRecipeStore(context: context).recipes(includingImages: false).map(\.content.name) == ["Landbrot"])
        #expect(try CoreDataPantryStore(context: context).items().isEmpty)
        #expect(!context.hasChanges)
    }

    @Test("A full backup comes in at once, its bakes and variants attached to the new recipes")
    func backupAttachesBakesAndVariants() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        var bread = RecipeStoreContract.bread()
        bread.bakeHistory = [RecipeExportBakeEntry(date: Date(timeIntervalSince1970: 1_800_000_000), comment: "gut",
                                                   images: [], facts: BakeHistoryFacts())]
        var variant = RecipeStoreContract.bread()
        variant.name = "Landbrot mit Saaten"
        variant.variantOf = bread.name
        variant.variantNote = "Saaten"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("atomic-\(UUID().uuidString).json")
        try RecipeExportFile(recipes: [bread, variant]).encoded().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try RecipeImport.importRecipes(from: url, into: context)
        #expect(result.recipes == 2)
        #expect(!context.hasChanges)
        let store = CoreDataRecipeStore(context: context)
        let recipes = try store.recipes(includingImages: false)
        let origin = try #require(recipes.first { $0.content.name == "Landbrot" })
        let copy = try #require(recipes.first { $0.content.name == "Landbrot mit Saaten" })
        #expect(copy.originID == origin.id && copy.variantNote == "Saaten")
        #expect(try CoreDataBakeHistoryStore(context: context).entries(ofRecipe: origin.id, includingImages: false).count == 1)
    }

    @Test("A recipe's UUID travels in the backup; restoring it twice adds nothing twice")
    func identityThroughCoreData() throws {
        let phone = PersistenceController(inMemory: true).container.viewContext
        let store = CoreDataRecipeStore(context: phone)
        let brot = try #require(try store.add(contentsOf: [RecipeStoreContract.bread()]).first)
        #expect(brot.backupID != nil)
        let file = try RecipeExportFile(recipeIDs: [brot.id], from: store,
                                        bakeHistory: CoreDataBakeHistoryStore(context: phone),
                                        starterFeedings: CoreDataStarterFeedingLogStore(context: phone))
        #expect(file.recipes.first?.backupID == brot.backupID)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID().uuidString).json")
        try file.encoded().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let tablet = PersistenceController(inMemory: true).container.viewContext
        #expect(try RecipeImport.restoreBackup(from: url, into: tablet).recipes == 1)
        #expect(try RecipeImport.restoreBackup(from: url, into: tablet).recipes == 0)
        let restored = try CoreDataRecipeStore(context: tablet).recipes(includingImages: false)
        #expect(restored.count == 1 && restored.first?.backupID == brot.backupID)
    }

    @Test("Import and restore read the file off the main thread and write it at once")
    func asyncImportAndRestore() async throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("async-\(UUID().uuidString).json")
        try RecipeExportFile(recipes: [RecipeStoreContract.bread()]).encoded().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try await RecipeImport.importRecipes(from: url, into: context).recipes == 1)
        #expect(try await RecipeImport.restoreBackup(from: url, into: context).recipes == 0)
        #expect(!context.hasChanges)
        #expect(try CoreDataRecipeStore(context: context).recipes(includingImages: false).count == 1)
    }
}

