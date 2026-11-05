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

    @Test("Files up to version 4 are read; the version after it is refused")
    func versions() throws {
        #expect(RecipeExportFile.isSupported(formatVersion: 1))
        #expect(RecipeExportFile.isSupported(formatVersion: 2))
        #expect(RecipeExportFile.isSupported(formatVersion: 3))
        #expect(RecipeExportFile.isSupported(formatVersion: 4))
        #expect(!RecipeExportFile.isSupported(formatVersion: 5))
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
