//
//  RecipeBackupTests.swift
//  BakePlannerCoreTests
//
//  Recipes moving through a backup file from one store into another, as
//  they will between an iPhone and an Android device.
//

import Foundation
import Testing
import BakePlannerCore

@Suite("Backup files and recipe stores")
struct RecipeBackupTests {

    private func twoRecipes() -> [RecipeExportData] {
        var zopf = RecipeStoreContract.bread()
        zopf.name = "Zopf"
        return [RecipeStoreContract.bread(), zopf]
    }

    @Test("A file written from one store reads into another as the same recipes")
    func roundTrip() throws {
        let source = InMemoryRecipeStore()
        let added = try source.add(contentsOf: twoRecipes())

        let file = try RecipeExportFile(recipeIDs: added.map(\.id).reversed(), from: source)
        #expect(file.recipes.map(\.name) == ["Zopf", "Landbrot"])

        let target = InMemoryRecipeStore()
        #expect(try RecipeImport.importFile(try file.encoded(), into: target) == 2)
        #expect(try target.recipes(includingImages: true).map(\.content)
                == (try source.recipes(includingImages: true).map(\.content)))
    }

    @Test("Reading a file twice keeps the recipes twice, as new recipes")
    func importTwice() throws {
        let data = try RecipeExportFile(recipes: twoRecipes()).encoded()
        let store = InMemoryRecipeStore()
        _ = try RecipeImport.importFile(data, into: store)
        _ = try RecipeImport.importFile(data, into: store)
        let recipes = try store.recipes(includingImages: false)
        #expect(recipes.count == 4)
        #expect(recipes.allSatisfy { $0.firestoreId == nil && !$0.bakeHistoryFlag })
    }

    @Test("A file from a newer version or no recipe file at all leaves the store as it was")
    func refusedFiles() throws {
        let store = InMemoryRecipeStore()
        var newer = RecipeExportFile(recipes: twoRecipes())
        newer.formatVersion = RecipeExportFile.currentFormatVersion + 1

        #expect(throws: RecipeImportError.unsupportedFormatVersion) {
            try RecipeImport.importFile(try newer.encoded(), into: store)
        }
        #expect(throws: RecipeImportError.unreadableFile) {
            try RecipeImport.importFile(Data("kein Rezept".utf8), into: store)
        }
        #expect(try store.recipes(includingImages: false).isEmpty)
    }

    @Test("A key the store no longer has is left out of the file")
    func missingKey() throws {
        let store = InMemoryRecipeStore()
        let added = try store.add(contentsOf: twoRecipes())
        try store.delete(id: added[0].id)
        let file = try RecipeExportFile(recipeIDs: added.map(\.id), from: store)
        #expect(file.recipes.map(\.name) == ["Zopf"])
    }
}
