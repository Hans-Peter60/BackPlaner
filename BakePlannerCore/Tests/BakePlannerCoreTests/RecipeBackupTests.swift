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
        #expect(try RecipeImport.importFile(try file.encoded(), into: target,
                                            bakeHistory: InMemoryBakeHistoryStore(recipes: target),
                                            starterFeedings: InMemoryStarterFeedingLogStore(recipes: target)) == 2)
        #expect(try target.recipes(includingImages: true).map(\.content)
                == (try source.recipes(includingImages: true).map(\.content)))
    }

    @Test("Reading a file twice keeps the recipes twice, as new recipes")
    func importTwice() throws {
        let data = try RecipeExportFile(recipes: twoRecipes()).encoded()
        let store = InMemoryRecipeStore()
        let history = InMemoryBakeHistoryStore(recipes: store)
        let feedings = InMemoryStarterFeedingLogStore(recipes: store)
        _ = try RecipeImport.importFile(data, into: store, bakeHistory: history, starterFeedings: feedings)
        _ = try RecipeImport.importFile(data, into: store, bakeHistory: history, starterFeedings: feedings)
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
            try RecipeImport.importFile(try newer.encoded(), into: store,
                                        bakeHistory: InMemoryBakeHistoryStore(recipes: store),
                                        starterFeedings: InMemoryStarterFeedingLogStore(recipes: store))
        }
        #expect(throws: RecipeImportError.unreadableFile) {
            try RecipeImport.importFile(Data("kein Rezept".utf8), into: store,
                                        bakeHistory: InMemoryBakeHistoryStore(recipes: store),
                                        starterFeedings: InMemoryStarterFeedingLogStore(recipes: store))
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

    // MARK: Bake history (format version 2)

    @Test("A file without bake history stays format version 1, as before")
    func plainFile() throws {
        let store = InMemoryRecipeStore()
        let history = InMemoryBakeHistoryStore(recipes: store)
        let added = try store.add(contentsOf: twoRecipes())

        let shared = try RecipeExportFile(recipeIDs: added.map(\.id), from: store)
        let backup = try RecipeExportFile(recipeIDs: added.map(\.id), from: store, bakeHistory: history,
                                          starterFeedings: InMemoryStarterFeedingLogStore(recipes: store))
        #expect(shared.formatVersion == RecipeExportFile.plainFormatVersion)
        #expect(backup.formatVersion == RecipeExportFile.plainFormatVersion)
        #expect(try backup.encoded() == shared.encoded())
        let text = String(decoding: try backup.encoded(), as: UTF8.self)
        #expect(!text.contains("bakeHistory"))
    }

    @Test("A backup carries the bake history into another store, attached to the new recipes")
    func bakeHistoryRoundTrip() throws {
        let source = InMemoryRecipeStore()
        let sourceHistory = InMemoryBakeHistoryStore(recipes: source)
        let added = try source.add(contentsOf: twoRecipes())
        let facts = BakeHistoryFacts(roomTemperature: 0, doughTemperature: 25.5, bulkProofMinutes: 210,
                                     flour: "Roggen 1150", outcome: "offen")
        let older = try sourceHistory.add(toRecipe: added[0].id, date: Date(timeIntervalSinceReferenceDate: 800_000_000.25),
                                          comment: "Gut", images: [Data([1, 2]), Data([3])], facts: facts)
        let newer = try sourceHistory.add(toRecipe: added[0].id, date: Date(timeIntervalSinceReferenceDate: 810_000_000),
                                          comment: "", images: [], facts: BakeHistoryFacts())

        let file = try RecipeExportFile(recipeIDs: added.map(\.id), from: source, bakeHistory: sourceHistory,
                                        starterFeedings: InMemoryStarterFeedingLogStore(recipes: source),
                                        shrinkPhoto: { $0 + Data([0xFF]) })
        #expect(file.formatVersion == 2)
        #expect(file.recipes[1].bakeHistory == nil)
        #expect(file.recipes[0].bakeHistory?.map(\.images) == [[], [Data([1, 2, 0xFF]), Data([3, 0xFF])]])

        let target = InMemoryRecipeStore()
        let targetHistory = InMemoryBakeHistoryStore(recipes: target)
        #expect(try RecipeImport.importFile(try file.encoded(), into: target, bakeHistory: targetHistory,
                                            starterFeedings: InMemoryStarterFeedingLogStore(recipes: target)) == 2)

        let bread = try #require(try target.recipes(includingImages: false).first { $0.content.name == "Landbrot" })
        let zopf = try #require(try target.recipes(includingImages: false).first { $0.content.name == "Zopf" })
        #expect(bread.bakeHistoryFlag && !zopf.bakeHistoryFlag)
        #expect(bread.content.bakeHistory == nil)
        let entries = try targetHistory.entries(ofRecipe: bread.id, includingImages: true)
        #expect(entries.map(\.date) == [newer.date, older.date])
        #expect(entries[1].comment == "Gut" && entries[1].facts == facts)
        #expect(entries[1].images == [Data([1, 2, 0xFF]), Data([3, 0xFF])])
        #expect(entries[0].facts == BakeHistoryFacts() && entries[0].comment == "")
    }

    @Test("Files up to version 7 are read; the version after it is refused")
    func versions() throws {
        for version in 1...7 {
            #expect(RecipeExportFile.isSupported(formatVersion: version))
        }
        #expect(!RecipeExportFile.isSupported(formatVersion: 8))
    }

    @Test("A backup carries the pantry; reading it fills an empty pantry and leaves known items alone")
    func pantryRoundTrip() throws {
        let source = InMemoryRecipeStore()
        let added = try source.add(contentsOf: twoRecipes())
        let sourcePantry = InMemoryPantryStore()
        _ = try sourcePantry.add(name: "Weizenmehl 550", amount: 2.5, unit: .kilogram,
                                 bestBefore: Date(timeIntervalSinceReferenceDate: 820_000_000), note: "Mühle Meier")
        _ = try sourcePantry.add(name: "Hefe", amount: 2, unit: .piece, bestBefore: nil, note: "")

        let file = try RecipeExportFile(recipeIDs: added.map(\.id), from: source,
                                        bakeHistory: InMemoryBakeHistoryStore(recipes: source),
                                        starterFeedings: InMemoryStarterFeedingLogStore(recipes: source),
                                        pantry: sourcePantry)
        #expect(file.formatVersion == 7)
        #expect(file.pantry == [
            RecipeExportPantryItem(name: "Hefe", amount: 2, unit: "St"),
            RecipeExportPantryItem(name: "Weizenmehl 550", amount: 2.5, unit: "kg",
                                   bestBefore: Date(timeIntervalSinceReferenceDate: 820_000_000), note: "Mühle Meier"),
        ])
        let data = try file.encoded()
        #expect(try RecipeImport.decodeFile(data) == file)

        let target = InMemoryRecipeStore()
        let targetPantry = InMemoryPantryStore()
        _ = try targetPantry.add(name: "hefe", amount: 1, unit: .piece, bestBefore: nil, note: "")
        let result = try RecipeImport.importFile(data, into: target, bakeHistory: InMemoryBakeHistoryStore(recipes: target),
                                                 starterFeedings: InMemoryStarterFeedingLogStore(recipes: target),
                                                 pantry: targetPantry)
        #expect(result == RecipeImportResult(recipes: 2, pantryItems: 1))
        let items = try targetPantry.items()
        #expect(items.map(\.name) == ["hefe", "Weizenmehl 550"])
        #expect(items[0].amount == 1)
        #expect(items[1].amount == 2.5 && items[1].unit == .kilogram && items[1].note == "Mühle Meier"
                && items[1].bestBefore == Date(timeIntervalSinceReferenceDate: 820_000_000))

        // The same file again: the recipes come once more, the pantry stays.
        let again = try RecipeImport.importFile(data, into: target, bakeHistory: InMemoryBakeHistoryStore(recipes: target),
                                                starterFeedings: InMemoryStarterFeedingLogStore(recipes: target),
                                                pantry: targetPantry)
        #expect(again == RecipeImportResult(recipes: 2, pantryItems: 0))
        #expect(try targetPantry.items().count == 2)

        // Without a pantry store (Android) the pantry is ignored, the count is the recipes.
        #expect(try RecipeImport.importFile(data, into: InMemoryRecipeStore(), bakeHistory: InMemoryBakeHistoryStore(recipes: target),
                                            starterFeedings: InMemoryStarterFeedingLogStore(recipes: target)) == 2)
    }

    @Test("An empty pantry leaves the file at its old version, without a pantry field")
    func emptyPantry() throws {
        let source = InMemoryRecipeStore()
        let added = try source.add(contentsOf: twoRecipes())
        let file = try RecipeExportFile(recipeIDs: added.map(\.id), from: source,
                                        bakeHistory: InMemoryBakeHistoryStore(recipes: source),
                                        starterFeedings: InMemoryStarterFeedingLogStore(recipes: source),
                                        pantry: InMemoryPantryStore())
        #expect(file.formatVersion == 1 && file.pantry == nil)
        #expect(!String(decoding: try file.encoded(), as: UTF8.self).contains("pantry"))
    }

    @Test("A step with oven settings makes the file version 6 and comes back with them")
    func ovenRoundTrip() throws {
        let source = InMemoryRecipeStore()
        var recipes = twoRecipes()
        recipes[0].instructions[0].oven = OvenSettings(temperature: 250, fallingTo: 220, steam: true)
        let added = try source.add(contentsOf: recipes)

        let file = try RecipeExportFile(recipeIDs: added.map(\.id), from: source,
                                        bakeHistory: InMemoryBakeHistoryStore(recipes: source),
                                        starterFeedings: InMemoryStarterFeedingLogStore(recipes: source))
        #expect(file.formatVersion == 6)
        let data = try file.encoded()
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"ovenTemperature\" : 250") && text.contains("\"ovenSteam\" : true"))
        // A step without settings writes none of the keys.
        #expect(text.components(separatedBy: "\"ovenTemperature\"").count == 2)

        let target = InMemoryRecipeStore()
        _ = try RecipeImport.importFile(data, into: target,
                                        bakeHistory: InMemoryBakeHistoryStore(recipes: target),
                                        starterFeedings: InMemoryStarterFeedingLogStore(recipes: target))
        let bread = try #require(try target.recipes(includingImages: false).first { $0.content.name != "Zopf" })
        #expect(bread.content.instructions[0].oven == OvenSettings(temperature: 250, fallingTo: 220, steam: true))
        #expect(bread.content.instructions[1].oven == nil)
    }

    @Test("A step with a duration window makes the file version 5 and comes back with it")
    func windowRoundTrip() throws {
        let source = InMemoryRecipeStore()
        var recipes = twoRecipes()
        recipes[0].instructions[0].durationWindow = 600...840
        let added = try source.add(contentsOf: recipes)

        let file = try RecipeExportFile(recipeIDs: added.map(\.id), from: source,
                                        bakeHistory: InMemoryBakeHistoryStore(recipes: source),
                                        starterFeedings: InMemoryStarterFeedingLogStore(recipes: source))
        #expect(file.formatVersion == 5)

        let target = InMemoryRecipeStore()
        _ = try RecipeImport.importFile(try file.encoded(), into: target,
                                        bakeHistory: InMemoryBakeHistoryStore(recipes: target),
                                        starterFeedings: InMemoryStarterFeedingLogStore(recipes: target))
        let bread = try #require(try target.recipes(includingImages: false).first { $0.content.name != "Zopf" })
        #expect(bread.content.instructions[0].durationWindow == 600...840)
        #expect(bread.content.instructions[1].durationWindow == nil)
    }

    @Test("A backup carries variants by their origin's name, and a rated bake makes it version 3")
    func variantsRoundTrip() throws {
        let source = InMemoryRecipeStore()
        let sourceHistory = InMemoryBakeHistoryStore(recipes: source)
        let added = try source.add(contentsOf: twoRecipes())
        var changed = RecipeStoreContract.bread()
        changed.name = "Landbrot – Dinkelmehl 630 (14.10.2026)"
        let variant = try source.addVariant(changed, of: added[0].id, note: "Dinkelmehl 630 statt Weizenmehl 550")
        _ = try sourceHistory.add(toRecipe: variant.id, date: Date(timeIntervalSinceReferenceDate: 800_000_000),
                                  comment: "Besser", images: [], facts: BakeHistoryFacts(rating: 5))
        let feedings = InMemoryStarterFeedingLogStore(recipes: source)

        // Shared on its own, a variant is a plain recipe in a version-1 file.
        let shared = try RecipeExportFile(recipeIDs: [variant.id], from: source)
        #expect(shared.formatVersion == 1)
        #expect(shared.recipes[0].variantOf == nil && shared.recipes[0].variantNote == nil)

        let file = try RecipeExportFile(recipeIDs: added.map(\.id) + [variant.id], from: source,
                                        bakeHistory: sourceHistory, starterFeedings: feedings)
        #expect(file.formatVersion == 3)
        #expect(file.recipes[2].variantOf == "Landbrot")
        #expect(file.recipes[2].variantNote == "Dinkelmehl 630 statt Weizenmehl 550")
        #expect(file.recipes[2].bakeHistory?.first?.rating == 5)
        #expect(file.recipes[0].variantOf == nil)

        // Read into another device: the variant hangs on the Landbrot read
        // from the same file, not on a Landbrot already there.
        let target = InMemoryRecipeStore()
        let targetHistory = InMemoryBakeHistoryStore(recipes: target)
        let older = try target.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        #expect(try RecipeImport.importFile(try file.encoded(), into: target, bakeHistory: targetHistory,
                                            starterFeedings: InMemoryStarterFeedingLogStore(recipes: target)) == 3)
        let recipes = try target.recipes(includingImages: false)
        let read = try #require(recipes.first { $0.content.name == changed.name })
        let origin = try #require(recipes.first { $0.content.name == "Landbrot" && $0.id != older.id })
        #expect(read.originID == origin.id)
        #expect(read.variantNote == "Dinkelmehl 630 statt Weizenmehl 550")
        #expect(read.content.variantOf == nil && read.content.variantNote == nil)
        #expect(try targetHistory.entries(ofRecipe: read.id, includingImages: false).first?.facts.rating == 5)

        // Without its origin in the file, a variant hangs on the recipe of
        // that name already on the device; without any, it stands alone.
        let alone = try RecipeExportFile(recipeIDs: [variant.id], from: source, bakeHistory: sourceHistory,
                                         starterFeedings: feedings)
        #expect(alone.formatVersion == 3)
        let second = InMemoryRecipeStore()
        let existing = try second.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        _ = try RecipeImport.importFile(try alone.encoded(), into: second, bakeHistory: InMemoryBakeHistoryStore(recipes: second),
                                        starterFeedings: InMemoryStarterFeedingLogStore(recipes: second))
        #expect(try second.recipes(includingImages: false).first { $0.content.name == changed.name }?.originID == existing.id)
        let third = InMemoryRecipeStore()
        _ = try RecipeImport.importFile(try alone.encoded(), into: third, bakeHistory: InMemoryBakeHistoryStore(recipes: third),
                                        starterFeedings: InMemoryStarterFeedingLogStore(recipes: third))
        let lone = try #require(try third.recipes(includingImages: false).first)
        #expect(lone.originID == nil && lone.variantNote == "Dinkelmehl 630 statt Weizenmehl 550")
    }

    @Test("A backup carries a starter's feedings into another store; a failed float test stays failed")
    func starterFeedingsRoundTrip() throws {
        let source = InMemoryRecipeStore()
        let sourceFeedings = InMemoryStarterFeedingLogStore(recipes: source)
        let added = try source.add(contentsOf: twoRecipes())
        let failed = try sourceFeedings.add(toRecipe: added[1].id, date: Date(timeIntervalSinceReferenceDate: 800_000_000.5),
                                            facts: StarterFeedingFacts(peakMinutes: 270, floatTestPassed: false,
                                                                       note: "träge"))
        let untested = try sourceFeedings.add(toRecipe: added[1].id, date: Date(timeIntervalSinceReferenceDate: 800_100_000),
                                              facts: StarterFeedingFacts())

        let file = try RecipeExportFile(recipeIDs: added.map(\.id), from: source,
                                        bakeHistory: InMemoryBakeHistoryStore(recipes: source),
                                        starterFeedings: sourceFeedings)
        #expect(file.formatVersion == 2)
        #expect(file.recipes[0].starterFeedings == nil && file.recipes[0].bakeHistory == nil)
        #expect(file.recipes[1].starterFeedings?.count == 2)

        let target = InMemoryRecipeStore()
        let targetFeedings = InMemoryStarterFeedingLogStore(recipes: target)
        _ = try RecipeImport.importFile(try file.encoded(), into: target,
                                        bakeHistory: InMemoryBakeHistoryStore(recipes: target),
                                        starterFeedings: targetFeedings)

        let zopf = try #require(try target.recipes(includingImages: false).first { $0.content.name == "Zopf" })
        #expect(!zopf.bakeHistoryFlag)
        #expect(zopf.content.starterFeedings == nil)
        let feedings = try targetFeedings.feedings(ofRecipe: zopf.id)
        #expect(feedings.map(\.date) == [untested.date, failed.date])
        #expect(feedings.map(\.facts) == [untested.facts, failed.facts])
    }

    @Test("A feeding with its room temperature makes the file version 4 and comes back with it")
    func feedingTemperatureRoundTrip() throws {
        let source = InMemoryRecipeStore()
        let sourceFeedings = InMemoryStarterFeedingLogStore(recipes: source)
        let added = try source.add(contentsOf: twoRecipes())
        let warm = try sourceFeedings.add(toRecipe: added[1].id, date: Date(timeIntervalSinceReferenceDate: 800_000_000),
                                          facts: StarterFeedingFacts(peakMinutes: 240, roomTemperature: 24.5))

        let file = try RecipeExportFile(recipeIDs: added.map(\.id), from: source,
                                        bakeHistory: InMemoryBakeHistoryStore(recipes: source),
                                        starterFeedings: sourceFeedings)
        #expect(file.formatVersion == 4)

        let target = InMemoryRecipeStore()
        let targetFeedings = InMemoryStarterFeedingLogStore(recipes: target)
        _ = try RecipeImport.importFile(try file.encoded(), into: target,
                                        bakeHistory: InMemoryBakeHistoryStore(recipes: target),
                                        starterFeedings: targetFeedings)
        let zopf = try #require(try target.recipes(includingImages: false).first { $0.content.name == "Zopf" })
        #expect(try targetFeedings.feedings(ofRecipe: zopf.id).map(\.facts) == [warm.facts])
        #expect(warm.facts.roomTemperature == 24.5)
    }
}
