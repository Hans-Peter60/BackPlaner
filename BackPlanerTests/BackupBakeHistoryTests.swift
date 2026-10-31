//
//  BackupBakeHistoryTests.swift
//  BackPlanerTests
//
//  The full backup with bake history (format version 2) through Core Data,
//  and the photos made smaller on the way into the file.
//

import BakePlannerCore
import CoreData
import Foundation
import Testing
import UIKit
@testable import BackPlaner

@Suite("Backup with bake history: Core Data")
@MainActor
struct BackupBakeHistoryTests {

    private func photo(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image { context in
                UIColor.brown.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            .jpegData(compressionQuality: 0.9)!
    }

    @Test("A camera-sized photo is brought down to the longest edge, keeping its proportions")
    func largePhotoShrinks() throws {
        let shrunk = BackupPhoto.shrunk(photo(width: 4032, height: 3024))
        let image = try #require(UIImage(data: shrunk))
        #expect(image.size.width * image.scale == 2048)
        #expect(image.size.height * image.scale == 1536)
    }

    @Test("A photo already small enough, and data that is no photo, stay exactly as they are")
    func smallPhotoStays() {
        let small = photo(width: 1200, height: 900)
        #expect(BackupPhoto.shrunk(small) == small)
        #expect(BackupPhoto.shrunk(Data([1, 2, 3])) == Data([1, 2, 3]))
    }

    @Test("Recipes and their bake history move from one device's Core Data to another's")
    func roundTrip() throws {
        let source = PersistenceController(inMemory: true).container.viewContext
        let recipes = CoreDataRecipeStore(context: source)
        let history = CoreDataBakeHistoryStore(context: source)
        let bread = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        let facts = BakeHistoryFacts(roomTemperature: 21, finalProofMinutes: 55, outcome: "offen")
        let entry = try history.add(toRecipe: bread.id, date: Date(timeIntervalSince1970: 1_800_000_000), comment: "Gut",
                                    images: [photo(width: 4032, height: 3024)], facts: facts)

        let file = try RecipeExportFile(recipeIDs: [bread.id], from: recipes, bakeHistory: history,
                                        shrinkPhoto: BackupPhoto.shrunk)
        #expect(file.formatVersion == 2)

        let target = PersistenceController(inMemory: true).container.viewContext
        let targetRecipes = CoreDataRecipeStore(context: target)
        let targetHistory = CoreDataBakeHistoryStore(context: target)
        #expect(try RecipeImport.importFile(try file.encoded(), into: targetRecipes, bakeHistory: targetHistory) == 1)

        let copy = try #require(try targetRecipes.recipes(includingImages: false).first)
        #expect(copy.bakeHistoryFlag)
        let entries = try targetHistory.entries(ofRecipe: copy.id, includingImages: true)
        #expect(entries.count == 1)
        #expect(entries.first?.date == entry.date)
        #expect(entries.first?.comment == "Gut")
        #expect(entries.first?.facts == facts)
        let image = try #require(entries.first?.images.first.flatMap(UIImage.init(data:)))
        #expect(image.size.width * image.scale == 2048)
    }
}
