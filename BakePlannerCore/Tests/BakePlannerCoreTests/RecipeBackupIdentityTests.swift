//
//  RecipeBackupIdentityTests.swift
//  BakePlannerCoreTests
//
//  A full backup carries each recipe's lasting identity (format 8), and
//  restoring it finds the recipe again by it. Matched by name, another
//  recipe of the same name took the backup's bakes and the backup's own
//  recipe was lost.
//

import Foundation
import Testing
import BakePlannerCore

@Suite("Restoring a backup finds its recipes by their identity")
struct RecipeBackupIdentityTests {

    private struct Device {
        let recipes = InMemoryRecipeStore()
        let history: InMemoryBakeHistoryStore
        let feedings: InMemoryStarterFeedingLogStore
        init() {
            history = InMemoryBakeHistoryStore(recipes: recipes)
            feedings = InMemoryStarterFeedingLogStore(recipes: recipes)
        }

        func backup() throws -> RecipeExportFile {
            try RecipeExportFile(recipeIDs: try recipes.recipes(includingImages: false).map(\.id),
                                 from: recipes, bakeHistory: history, starterFeedings: feedings)
        }

        func restore(_ file: RecipeExportFile) throws -> RecipeImportResult {
            try RecipeImport.restoreBackup(try file.encoded(), into: recipes, bakeHistory: history,
                                           starterFeedings: feedings, pantry: nil)
        }

        func bakes(of name: String) throws -> Int {
            guard let recipe = try recipes.recipes(includingImages: false).first(where: { $0.content.name == name })
            else { return -1 }
            return try history.entries(ofRecipe: recipe.id, includingImages: false).count
        }
    }

    private func day(_ offset: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + offset * 86_400) }

    @Test("A full backup carries identities without raising its version; a shared recipe carries none")
    func backupCarriesIdentity() throws {
        let device = Device()
        let added = try device.recipes.add(contentsOf: [RecipeStoreContract.bread()])
        let file = try device.backup()
        // An older app reads the file and only loses the identity.
        #expect(file.formatVersion == RecipeExportFile.plainFormatVersion)
        #expect(file.recipes.first?.backupID == added.first?.backupID && added.first?.backupID != nil)
        let shared = try RecipeExportFile(recipeIDs: added.map(\.id), from: device.recipes)
        #expect(shared.recipes.first?.backupID == nil && shared.formatVersion == 1)
        // What the store hands out carries no identity in its content.
        #expect(try device.recipes.recipes(includingImages: false).first?.content.backupID == nil)
    }

    @Test("Another recipe of the same name keeps its bakes; the backup's comes in beside it")
    func namesakeStaysApart() throws {
        let phone = Device()
        let brot = try #require(try phone.recipes.add(contentsOf: [RecipeStoreContract.bread()]).first)
        _ = try phone.history.add(toRecipe: brot.id, date: day(1), comment: "aus der Sicherung", images: [], facts: BakeHistoryFacts())
        let file = try phone.backup()

        let other = Device()
        var different = RecipeStoreContract.bread()
        different.summary = "Ganz anderes Landbrot"
        let mine = try #require(try other.recipes.add(contentsOf: [different]).first)
        _ = try other.history.add(toRecipe: mine.id, date: day(2), comment: "eigenes", images: [], facts: BakeHistoryFacts())

        let result = try other.restore(file)
        #expect(result.recipes == 1 && result.bakeEntries == 0)
        let breads = try other.recipes.recipes(includingImages: false).filter { $0.content.name == brot.content.name }
        #expect(breads.count == 2)
        let counts = try breads.map { try other.history.entries(ofRecipe: $0.id, includingImages: false).map(\.comment) }
        #expect(counts.sorted { $0.first ?? "" < $1.first ?? "" } == [["aus der Sicherung"], ["eigenes"]])
    }

    @Test("Restoring the same backup twice adds nothing twice")
    func restoreTwice() throws {
        let phone = Device()
        let brot = try #require(try phone.recipes.add(contentsOf: [RecipeStoreContract.bread()]).first)
        _ = try phone.history.add(toRecipe: brot.id, date: day(1), comment: "", images: [], facts: BakeHistoryFacts())
        let file = try phone.backup()

        let newPhone = Device()
        #expect(try newPhone.restore(file).recipes == 1)
        let again = try newPhone.restore(file)
        #expect(again.recipes == 0 && again.bakeEntries == 0)
        #expect(try newPhone.recipes.recipes(includingImages: false).count == 1)
        #expect(try newPhone.bakes(of: brot.content.name) == 1)
    }

    @Test("A renamed recipe is still found by its identity and gets the bakes it lacks")
    func renamedRecipeFound() throws {
        let phone = Device()
        let brot = try #require(try phone.recipes.add(contentsOf: [RecipeStoreContract.bread()]).first)
        _ = try phone.history.add(toRecipe: brot.id, date: day(1), comment: "", images: [], facts: BakeHistoryFacts())
        let file = try phone.backup()

        // The backup goes onto a second phone, the recipe is renamed there,
        // then the backup — with one more bake since — comes in again.
        let second = Device()
        _ = try second.restore(file)
        var renamed = try #require(try second.recipes.recipes(includingImages: false).first)
        renamed.content.name = "Mein Landbrot"
        try second.recipes.update(renamed)
        _ = try phone.history.add(toRecipe: brot.id, date: day(3), comment: "", images: [], facts: BakeHistoryFacts())

        let result = try second.restore(try phone.backup())
        #expect(result.recipes == 0 && result.bakeEntries == 1)
        #expect(try second.bakes(of: "Mein Landbrot") == 2)
    }

    @Test("A recipe read in once with an import is the same recipe when it reads the same")
    func importedThenRestored() throws {
        let phone = Device()
        let brot = try #require(try phone.recipes.add(contentsOf: [RecipeStoreContract.bread()]).first)
        _ = try phone.history.add(toRecipe: brot.id, date: day(1), comment: "", images: [], facts: BakeHistoryFacts())
        let file = try phone.backup()

        let tablet = Device()
        _ = try RecipeImport.importFile(try file.encoded(), into: tablet.recipes, bakeHistory: tablet.history,
                                        starterFeedings: tablet.feedings, pantry: nil)
        // An import gives a new identity: reading a file twice makes two.
        #expect(try tablet.recipes.recipes(includingImages: false).first?.backupID != brot.backupID)
        let result = try tablet.restore(file)
        #expect(result.recipes == 0)
        #expect(try tablet.recipes.recipes(includingImages: false).count == 1)
    }

    @Test("A backup without identities (format 7 and older) still goes by the name")
    func olderBackupByName() throws {
        let phone = Device()
        let brot = try #require(try phone.recipes.add(contentsOf: [RecipeStoreContract.bread()]).first)
        _ = try phone.history.add(toRecipe: brot.id, date: day(1), comment: "", images: [], facts: BakeHistoryFacts())
        var file = try phone.backup()
        file.recipes = file.recipes.map { var recipe = $0; recipe.backupID = nil; return recipe }
        file.formatVersion = 7

        let other = Device()
        var different = RecipeStoreContract.bread()
        different.summary = "anders"
        _ = try other.recipes.add(contentsOf: [different])
        let result = try other.restore(file)
        #expect(result.recipes == 0 && result.bakeEntries == 1)
    }
}
