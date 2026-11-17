//
//  RecipeImportLenientTests.swift
//  BakePlannerCoreTests
//
//  A backup or shared file is read as far as it can be: a recipe that
//  cannot be read is left out and counted instead of failing the file, a
//  field an older or hand-made file lacks takes its empty value, and a
//  pantry item without a name no longer stops the import.
//

import Foundation
import Testing
import BakePlannerCore

@Suite("Backup files are read as far as they can be")
struct RecipeImportLenientTests {

    private func stores() -> (InMemoryRecipeStore, InMemoryBakeHistoryStore, InMemoryStarterFeedingLogStore) {
        let recipes = InMemoryRecipeStore()
        return (recipes, InMemoryBakeHistoryStore(recipes: recipes), InMemoryStarterFeedingLogStore(recipes: recipes))
    }

    @Test("Unreadable recipes are left out and counted; a wrong field takes its empty value")
    func skipsUnreadableRecipe() throws {
        let json = """
        {"formatVersion": 1, "recipes": [
          {"name": "Landbrot", "summary": "", "prepTime": 60, "totalWeight": 900, "tags": [], "rating": 4,
           "recurrenceIntervalDays": 0, "components": [], "instructions": []},
          {"name": "Zopf", "rating": "sehr gut", "components": [], "instructions": []},
          {"name": "Kaputt", "components": "keine", "instructions": []},
          {"summary": "ohne Namen"}]}
        """
        let (recipes, history, feedings) = stores()
        let result = try RecipeImport.importFile(Data(json.utf8), into: recipes, bakeHistory: history,
                                                 starterFeedings: feedings, pantry: nil)
        #expect(result.recipes == 2 && result.skippedRecipes == 2)
        #expect(result.skippedNote?.contains("2") == true)
        // A field of the wrong type takes its empty value; the recipe comes in.
        let names = try recipes.recipes(includingImages: false).map { ($0.content.name, $0.content.rating) }
        #expect(names.map(\.0) == ["Landbrot", "Zopf"] && names.map(\.1) == [4, 0])
    }

    @Test("Fields an older or hand-made file lacks take their empty value")
    func missingFields() throws {
        let json = """
        {"recipes": [{"name": "Zopf",
          "components": [{"name": "Teig", "ingredients": [{"name": "Mehl", "weight": 500}]}],
          "instructions": [{"instruction": "Kneten", "step": 1, "duration": 10}]}]}
        """
        let file = try RecipeImport.decodeFile(Data(json.utf8))
        let recipe = try #require(file.recipes.first)
        #expect(file.formatVersion == 1 && file.skippedRecipes == 0)
        #expect(recipe.tags.isEmpty && recipe.rating == 0 && recipe.summary.isEmpty)
        let ingredient = try #require(recipe.components.first?.ingredients.first)
        #expect(ingredient.normWeight == 500 && ingredient.num == 0 && ingredient.denom == 0)
        #expect(recipe.instructions.first?.startTime == 0 && recipe.instructions.first?.bakeFlag == false)
    }

    @Test("A file whose recipes are all unreadable is no recipe file")
    func allUnreadable() {
        let json = #"{"formatVersion": 1, "recipes": [{"rating": 1}, 42]}"#
        #expect(throws: RecipeImportError.self) { try RecipeImport.decodeFile(Data(json.utf8)) }
        #expect(throws: RecipeImportError.self) { try RecipeImport.decodeFile(Data("kein json".utf8)) }
    }

    @Test("The file as written is unchanged: the count of left-out recipes is not part of it")
    func formatUnchanged() throws {
        let file = RecipeExportFile(recipes: [RecipeStoreContract.bread()])
        let text = String(decoding: try file.encoded(), as: UTF8.self)
        #expect(!text.contains("skipped"))
        #expect(try RecipeImport.decodeFile(try file.encoded()) == file)
    }

    @Test("A pantry item without a name is left out instead of stopping the import")
    func blankPantryItem() throws {
        let file = RecipeExportFile(recipes: [RecipeStoreContract.bread()], pantry: [
            RecipeExportPantryItem(name: "  ", amount: 1, unit: "kg"),
            RecipeExportPantryItem(name: "Roggenmehl", amount: 2, unit: "kg"),
        ])
        let (recipes, history, feedings) = stores()
        let pantry = InMemoryPantryStore()
        let result = try RecipeImport.importFile(try file.encoded(), into: recipes, bakeHistory: history,
                                                 starterFeedings: feedings, pantry: pantry)
        #expect(result.recipes == 1 && result.pantryItems == 1)
        #expect(try pantry.items().map(\.name) == ["Roggenmehl"])
    }

    @Test("A store's refusal reads as a sentence, not as a code")
    func storeErrorsAreLocalized() {
        #expect(PantryStoreError.emptyName.localizedDescription.contains("nichts übernommen"))
        #expect(RecipeStoreError.unknownRecipe("x").errorDescription != nil)
        #expect(BakeHistoryStoreError.unknownRecipe("x").errorDescription != nil)
        #expect(StarterFeedingLogStoreError.unknownRecipe("x").errorDescription != nil)
    }

    @Test("A file far larger than any backup is refused before it is read")
    func refusesHugeFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("huge-\(UUID().uuidString).json")
        // A sparse file: its size is set, its bytes are never written.
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(RecipeImport.maximumFileBytes + 1))
        try handle.close()
        #expect(throws: RecipeImportError.fileTooLarge) { try RecipeImport.readFile(at: url) }

        let small = FileManager.default.temporaryDirectory.appendingPathComponent("small-\(UUID().uuidString).json")
        try RecipeExportFile(recipes: [RecipeStoreContract.bread()]).encoded().write(to: small)
        defer { try? FileManager.default.removeItem(at: small) }
        #expect(try RecipeImport.decodeFile(try RecipeImport.readFile(at: small)).recipes.count == 1)
        #expect(throws: RecipeImportError.unreadableFile) {
            try RecipeImport.readFile(at: small.appendingPathExtension("fehlt"))
        }
    }

    @Test("A file read off the main thread imports and restores like its bytes")
    func decodedOffTheMainThread() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("decoded-\(UUID().uuidString).json")
        try RecipeExportFile(recipes: [RecipeStoreContract.bread()]).encoded().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try await RecipeImport.decodedFile(at: url)
        let (recipes, history, feedings) = stores()
        #expect(try RecipeImport.importFile(file, into: recipes, bakeHistory: history, starterFeedings: feedings,
                                            pantry: nil).recipes == 1)
        #expect(try RecipeImport.restoreBackup(file, into: recipes, bakeHistory: history, starterFeedings: feedings,
                                               pantry: nil).recipes == 0)
        await #expect(throws: RecipeImportError.unreadableFile) {
            try await RecipeImport.decodedFile(at: url.appendingPathExtension("fehlt"))
        }
    }
}
