//
//  SQLiteAtomicImportTests.swift
//  BakePlannerStorageTests
//
//  An import on Android writes recipes, bakes, feedings and pantry items
//  through four stores on one file. `atomically` keeps all of it or, when
//  anything fails, none — the stores' own transactions nest inside.
//

import BakePlannerCore
import BakePlannerStorage
import Foundation
import Testing

@Suite("Imports on Android: all or nothing")
struct SQLiteAtomicImportTests {

    struct Stop: Error {}

    @Test("A failure half-way leaves the database as it was")
    func failureKeepsNothing() throws {
        let store = try SQLiteRecipeStore(path: nil)
        defer { try? store.close() }
        let pantry = SQLitePantryStore(file: store.file)
        _ = try store.add(contentsOf: [RecipeStoreContract.bread()])

        #expect(throws: Stop.self) {
            try store.file.atomically {
                var zopf = RecipeStoreContract.bread()
                zopf.name = "Zopf"
                _ = try store.add(contentsOf: [zopf])
                _ = try pantry.add(name: "Hefe", amount: 42, unit: .gram, bestBefore: nil, note: "")
                throw Stop()
            }
        }
        #expect(try store.recipes(includingImages: false).map(\.content.name) == ["Landbrot"])
        #expect(try pantry.items().isEmpty)
    }

    @Test("An import that succeeds keeps everything, with the stores' transactions nested inside")
    func successKeepsAll() throws {
        let store = try SQLiteRecipeStore(path: nil)
        defer { try? store.close() }
        let history = SQLiteBakeHistoryStore(file: store.file)
        let feedings = SQLiteStarterFeedingLogStore(file: store.file)
        var bread = RecipeStoreContract.bread()
        bread.bakeHistory = [RecipeExportBakeEntry(date: Date(timeIntervalSince1970: 1_800_000_000), comment: "gut", images: [], facts: BakeHistoryFacts())]
        let data = try RecipeExportFile(recipes: [bread]).encoded()

        let result = try store.file.atomically {
            try RecipeImport.importFile(data, into: store, bakeHistory: history, starterFeedings: feedings, pantry: nil)
        }
        #expect(result.recipes == 1)
        let recipe = try #require(try store.recipes(includingImages: false).first)
        #expect(try history.entries(ofRecipe: recipe.id, includingImages: false).count == 1)
        // The file stays usable for writes outside the import.
        _ = try store.add(contentsOf: [RecipeStoreContract.bread()])
        #expect(try store.recipes(includingImages: false).count == 2)
    }
}
