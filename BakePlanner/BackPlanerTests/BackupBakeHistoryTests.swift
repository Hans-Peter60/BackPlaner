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

    /// A picture with detail in it, so that it weighs like a photo does and
    /// gets smaller when shrunk — a plain colour hardly does either.
    private func detailedPhoto(width: CGFloat, height: CGFloat, quality: CGFloat = 1.0) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var generator = SystemRandomNumberGenerator()
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image { context in
                for _ in 0..<4000 {
                    UIColor(hue: CGFloat.random(in: 0...1, using: &generator), saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                    context.fill(CGRect(x: CGFloat.random(in: 0..<width, using: &generator),
                                        y: CGFloat.random(in: 0..<height, using: &generator),
                                        width: CGFloat.random(in: 3...60, using: &generator),
                                        height: CGFloat.random(in: 3...60, using: &generator)))
                }
            }
            .jpegData(compressionQuality: quality)!
    }

    private func recipe(_ name: String, picture: Data, photos: [Data]) -> RecipeExportData {
        var recipe = RecipeStoreContract.bread()
        recipe.name = name
        recipe.image = picture
        recipe.bakeHistory = photos.isEmpty ? nil : [
            RecipeExportBakeEntry(date: Date(timeIntervalSince1970: 1_800_000_000), comment: "Gut", images: photos, facts: BakeHistoryFacts())
        ]
        return recipe
    }

    private func pixels(_ data: Data?) throws -> CGFloat {
        let image = try #require(data.flatMap(UIImage.init(data:)))
        return max(image.size.width, image.size.height) * image.scale
    }

    @Test("A backup over the limit shrinks its pictures only as far as needed, keeping every recipe")
    func oversizedBackupFits() throws {
        let picture = detailedPhoto(width: 4032, height: 3024)
        let photo = detailedPhoto(width: 4032, height: 3024)
        let file = RecipeExportFile(recipes: (1...3).map { recipe("Brot \($0)", picture: picture, photos: [photo]) })
        let size = try file.encoded().count
        let limit = size / 3

        let fitted = BackupSizeLimit.fit(file, limit: limit)
        #expect(try fitted.encoded().count <= limit)
        // The size estimate the fitting works with is close to, and never below, the real size.
        let text = try BackupSizeLimit.encodedSizeWithoutPictures(fitted)
        let estimate = BackupSizeLimit.encodedSize(fitted, text: text)
        let actual = try fitted.encoded().count
        #expect(estimate >= actual, "estimate \(estimate), actual \(actual), text \(text)")
        #expect(estimate <= actual + 6 * BackupSizeLimit.pictureOverhead)
        #expect(fitted.recipes.count == 3)
        #expect(fitted.recipes.map(\.name) == ["Brot 1", "Brot 2", "Brot 3"])
        let pictureEdge = try pixels(fitted.recipes[0].image)
        let photoEdge = try pixels(fitted.recipes[0].bakeHistory?.first?.images.first)
        #expect(pictureEdge < 4032 && pictureEdge >= BackupSizeLimit.levels.last!.edge)
        // Photos go one step ahead of the pictures.
        #expect(photoEdge <= pictureEdge)
        // Not smaller than needed: the level before, reached the same way
        // (each level from the one before it), would not have fitted.
        let level = try #require(BackupSizeLimit.levels.firstIndex { $0.edge == pictureEdge })
        if level > 0 {
            var larger = file
            for index in 0..<level {
                larger = BackupSizeLimit.shrink(larger, pictures: BackupSizeLimit.levels[index],
                                                photos: BackupSizeLimit.levels[min(index + 1, BackupSizeLimit.levels.count - 1)])
            }
            #expect(try larger.encoded().count > limit)
        }
    }

    @Test("A backup within the limit keeps its pictures exactly as they are")
    func smallBackupStays() throws {
        let file = RecipeExportFile(recipes: [recipe("Brot", picture: detailedPhoto(width: 1600, height: 1200), photos: [])])
        #expect(BackupSizeLimit.fit(file) == file)
    }

    @Test("When even the smallest pictures do not fit, the bake-history photos go and the recipe pictures stay")
    func photosGoBeforePictures() throws {
        let file = RecipeExportFile(recipes: [recipe("Brot", picture: detailedPhoto(width: 4032, height: 3024),
                                                     photos: [detailedPhoto(width: 4032, height: 3024)])])
        let fitted = BackupSizeLimit.fit(file, limit: 1000)
        #expect(fitted.recipes[0].bakeHistory?.first?.images.isEmpty == true)
        #expect(try pixels(fitted.recipes[0].image) == BackupSizeLimit.levels.last!.edge)
    }

    @Test("A full-quality recipe picture within the edge is re-encoded only when asked, and only if that helps")
    func recompression() throws {
        let fullQuality = detailedPhoto(width: 1600, height: 1200, quality: 1.0)
        let recompressed = BackupPhoto.shrunk(fullQuality, longestEdge: 2048, quality: 0.7)
        #expect(recompressed.count < fullQuality.count)
        #expect(try pixels(recompressed) == 1600)
        #expect(BackupPhoto.shrunk(fullQuality, longestEdge: 2048, quality: 0.7, recompressingSmaller: false) == fullQuality)
        let tiny = detailedPhoto(width: 400, height: 300, quality: 0.3)
        #expect(BackupPhoto.shrunk(tiny, longestEdge: 2048, quality: 0.9) == tiny)
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
                                        starterFeedings: CoreDataStarterFeedingLogStore(context: source),
                                        shrinkPhoto: BackupPhoto.shrunk)
        #expect(file.formatVersion == 2)

        let target = PersistenceController(inMemory: true).container.viewContext
        let targetRecipes = CoreDataRecipeStore(context: target)
        let targetHistory = CoreDataBakeHistoryStore(context: target)
        #expect(try RecipeImport.importFile(try file.encoded(), into: targetRecipes, bakeHistory: targetHistory,
                                            starterFeedings: CoreDataStarterFeedingLogStore(context: target)) == 1)

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
