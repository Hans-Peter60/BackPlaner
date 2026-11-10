//
//  RecipeExport.swift
//  BackPlaner
//
//  A recipe (or several) as a self-contained JSON file: everything needed to
//  recreate it on another device or hand it to someone else without putting
//  it in the public database — the one thing the manual still lists as
//  missing. A recipe shared with someone else leaves the bake history out:
//  that is this device's record of what actually happened, not part of the
//  recipe, the same boundary "Rezept veröffentlichen" draws for the public
//  database. The full backup from the settings carries it along, and the
//  starter feeding diary too (format version 2), so both move to a new
//  device with the recipes.
//

import BakePlannerCore
import Foundation
import CoreData
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Recipe → export data

extension RecipeExportData {
    init(recipe: Recipe) {
        self.init(recipe: recipe, includingImage: true)
    }

    /// `includingImage: false` leaves the image out: the calculations need
    /// only the content, and need not carry the picture around.
    init(recipe: Recipe, includingImage: Bool) {
        // Another module's struct: its own initializer sets the fields.
        self.init(
            name: recipe.name,
            summary: recipe.summary,
            urlLink: recipe.urlLink,
            prepTime: recipe.prepTime,
            totalWeight: recipe.totalWeight,
            tags: recipe.tags,
            rating: recipe.rating,
            recurrenceIntervalDays: recipe.recurrenceIntervalDays,
            image: includingImage && !recipe.image.isEmpty ? recipe.image : nil,
            components: recipe.componentsArray.map { component in
                RecipeExportComponent(
                    name: component.name,
                    number: component.number,
                    ingredients: component.ingredientsArray.map { ingredient in
                        RecipeExportIngredient(
                            name: ingredient.name,
                            number: ingredient.number,
                            unit: ingredient.unit,
                            weight: ingredient.weight,
                            normWeight: ingredient.normWeight,
                            num: ingredient.num,
                            denom: ingredient.denom
                        )
                    }
                )
            },
            instructions: recipe.instructionsArray.map { instruction in
                RecipeExportInstruction(
                    instruction: instruction.instruction,
                    step: instruction.step,
                    duration: instruction.duration,
                    startTime: instruction.startTime,
                    bakeFlag: instruction.bakeFlag,
                    componentName: instruction.componentName,
                    minDuration: instruction.durationWindow?.lowerBound,
                    maxDuration: instruction.durationWindow?.upperBound,
                    oven: instruction.oven
                )
            }
        )
    }
}

extension RecipeExportData {
    /// A recipe from the public database, with its picture from the download
    /// cache (the package's `init(recipeFB:imageData:)`).
    init(recipeFB: RecipeFB, image: UIImage?) {
        self.init(recipeFB: recipeFB, imageData: image?.jpegData(compressionQuality: 1.0))
    }
}

// MARK: - Export data → recipe

extension RecipeExportData {
    /// Builds a brand-new recipe from this data — always a fresh `Recipe`
    /// with its own id, never matched against an existing one by name, so
    /// importing can never silently overwrite a recipe already on the
    /// device.
    func makeRecipe(in context: NSManagedObjectContext) -> Recipe {
        let recipe = Recipe(context: context)
        recipe.id                     = UUID()
        recipe.name                   = name
        recipe.summary                = summary
        recipe.urlLink                = urlLink
        recipe.prepTime               = prepTime
        recipe.totalWeight            = totalWeight
        recipe.tags                   = tags
        recipe.rating                 = rating
        recipe.recurrenceIntervalDays = recurrenceIntervalDays
        recipe.image                  = image ?? Data()

        for componentData in components {
            let component    = Component(context: context)
            component.id      = UUID()
            component.name    = componentData.name
            component.number  = componentData.number

            for ingredientData in componentData.ingredients {
                let ingredient       = Ingredient(context: context)
                ingredient.id         = UUID()
                ingredient.name       = ingredientData.name
                ingredient.number     = ingredientData.number
                ingredient.unit       = ingredientData.unit
                ingredient.weight     = ingredientData.weight
                ingredient.normWeight = ingredientData.normWeight
                ingredient.num        = ingredientData.num
                ingredient.denom      = ingredientData.denom
                component.addToIngredients(ingredient)
            }

            recipe.addToComponents(component)
        }

        for instructionData in instructions {
            let instruction           = Instruction(context: context)
            instruction.id            = UUID()
            instruction.instruction   = instructionData.instruction
            instruction.step          = instructionData.step
            instruction.duration      = instructionData.duration
            instruction.startTime     = instructionData.startTime
            instruction.bakeFlag      = instructionData.bakeFlag
            instruction.componentName = instructionData.componentName
            instruction.durationWindow = instructionData.durationWindow
            recipe.addToInstructions(instruction)
        }

        return recipe
    }
}

// MARK: - Share sheet item

/// What `ShareLink` hands to the share sheet: one recipe, or — from the
/// settings backup — every recipe on the device, as one file either way.
struct RecipeFileExport: FileExport {
    /// The recipes by id, read again only when the file is actually handed
    /// over. A `ShareLink` builds its item on every layout of the screen it
    /// sits in, and the item used to carry the finished export — every
    /// recipe with its components, steps and picture copied into the export
    /// structure. In the settings that happened on each keystroke in the
    /// text field next to it, and typing there stuttered.
    private let recipeIDs: [NSManagedObjectID]
    let fileName: String
    /// True for the full backup: the recipes' bake history goes along.
    private let includesBakeHistory: Bool

    /// One recipe to share, without its bake history.
    init(recipe: Recipe) {
        self.init(recipes: [recipe], fileName: recipe.name.isEmpty ? "Rezept" : recipe.name,
                  includesBakeHistory: false)
    }

    /// The backup of `recipes`, with their bake history.
    init(recipes: [Recipe], fileName: String) {
        self.init(recipes: recipes, fileName: fileName, includesBakeHistory: true)
    }

    /// A chosen set of recipes, with or without their bake history and
    /// feeding diaries (RecipeExportSelectionView).
    init(recipes: [Recipe], fileName: String, includesBakeHistory: Bool) {
        recipeIDs = recipes.map(\.objectID)
        self.fileName = Self.sanitizedFileName(fileName)
        self.includesBakeHistory = includesBakeHistory
    }

    /// The export as it stands when the file is written.
    var file: RecipeExportFile {
        let context = PersistenceController.shared.container.viewContext
        var file = RecipeExportFile(recipes: [])
        context.performAndWait {
            if includesBakeHistory {
                let keys = recipeIDs.map { $0.uriRepresentation().absoluteString }
                if let backup = try? RecipeExportFile(recipeIDs: keys, from: CoreDataRecipeStore(context: context),
                                                      bakeHistory: CoreDataBakeHistoryStore(context: context),
                                                      starterFeedings: CoreDataStarterFeedingLogStore(context: context),
                                                      shrinkPhoto: BackupPhoto.shrunk) {
                    file = backup
                    return
                }
            }
            file = RecipeExportFile(recipes: recipeIDs
                .compactMap { try? context.existingObject(with: $0) as? Recipe }
                .map(RecipeExportData.init))
        }
        return BackupSizeLimit.fit(file)
    }

    /// The full backup's name, dated: `BakePlanner-Rezepte-2026-11-10`.
    static var backupFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "BakePlanner-Rezepte-\(formatter.string(from: Date()))"
    }

    private static func sanitizedFileName(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
            .joined(separator: "-")
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            SentTransferredFile(try export.writeFile())
        }
        .suggestedFileName { "\($0.fileName).json" }
    }

    /// The file in the temporary folder, written now (FileShareLink on the Mac).
    func writeFile() throws -> URL {
        let data = try file.encoded()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
            .appendingPathExtension("json")
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Import

extension RecipeImport {
    /// Decodes a backup/share file and writes every recipe it holds into the
    /// context as new recipes, returning how many were added.
    @discardableResult
    static func importRecipes(from url: URL, into context: NSManagedObjectContext) throws -> Int {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if needsSecurityScope { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RecipeImportError.unreadableFile
        }

        return try importFile(data, into: CoreDataRecipeStore(context: context),
                              bakeHistory: CoreDataBakeHistoryStore(context: context),
                              starterFeedings: CoreDataStarterFeedingLogStore(context: context))
    }
}

// MARK: - Photos in the backup

/// The bake photos as the backup carries them: no longer edge than looks
/// sharp on the largest screen they are shown on — the photo opened full
/// screen on a 13-inch iPad — instead of the camera's 12 or 48 megapixels.
enum BackupPhoto {
    /// Pixels on the longer side.
    static let longestEdge: CGFloat = 2048
    static let jpegQuality: CGFloat = 0.8

    /// The photo at most `longestEdge` pixels long, as JPEG. One already
    /// that small, or one that is no picture, stays exactly as it is.
    static func shrunk(_ data: Data) -> Data {
        shrunk(data, longestEdge: longestEdge, quality: jpegQuality, recompressingSmaller: false)
    }

    /// The picture at most `longestEdge` pixels long as JPEG of `quality`.
    /// With `recompressingSmaller`, a picture already within the edge is
    /// re-encoded at `quality` all the same when that makes it smaller — a
    /// recipe picture is stored at full JPEG quality — and kept as it is
    /// otherwise. Data that is no picture stays untouched.
    static func shrunk(_ data: Data, longestEdge: CGFloat, quality: CGFloat, recompressingSmaller: Bool = true) -> Data {
        // Everything ImageIO and UIKit hand out on the way is released
        // before the next picture; seventy camera pictures in one go
        // otherwise fill the memory an iPhone grants the app.
        autoreleasepool {
            guard let image = UIImage(data: data) else { return data }
            let longest = max(image.size.width, image.size.height) * image.scale
            if longest <= longestEdge {
                guard recompressingSmaller,
                      let reencoded = image.jpegData(compressionQuality: quality), reencoded.count < data.count else { return data }
                return reencoded
            }
            // ImageIO scales while it decodes: a 12-megapixel picture never
            // becomes a 48 MB bitmap, only the small one is drawn.
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let resized = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceShouldCacheImmediately: true,
                      kCGImageSourceThumbnailMaxPixelSize: Int(longestEdge),
                  ] as CFDictionary) else { return data }
            return UIImage(cgImage: resized).jpegData(compressionQuality: quality) ?? data
        }
    }
}

/// Keeps a backup file within a size the share sheet, Mail and AirDrop
/// handle comfortably. Seventy recipes with their pictures at full camera
/// quality made a 47 MB file; the pictures are what weighs. The pictures
/// are shrunk in steps — first to the size a recipe page needs, then
/// smaller — until the encoded file is within `limit`, and only as far as
/// needed, so a small backup keeps its pictures sharp. Bake-history photos
/// shrink one step ahead of the recipe pictures and are the first to go
/// if even the smallest pictures do not fit; recipe pictures are never
/// dropped.
enum BackupSizeLimit {
    /// 5 MB, as Hans-Peter asked for all of his recipes in one file.
    static let maximumBytes = 5 * 1024 * 1024

    /// Longest edge and JPEG quality, largest first.
    static let levels: [(edge: CGFloat, quality: CGFloat)] = [
        (2048, 0.8), (1280, 0.75), (1024, 0.7), (768, 0.65), (640, 0.6), (512, 0.55), (384, 0.5)
    ]

    static func fit(_ file: RecipeExportFile, limit: Int = maximumBytes) -> RecipeExportFile {
        guard let text = try? encodedSizeWithoutPictures(file) else { return file }
        guard encodedSize(file, text: text) > limit else { return file }
        var fitted = file
        for (index, level) in levels.enumerated() {
            // The photos one level smaller than the pictures, the last level for both.
            let photoLevel = levels[min(index + 1, levels.count - 1)]
            // Each level starts from the one before: the pictures are small
            // by then, and the camera-sized originals are read only once.
            fitted = shrink(fitted, pictures: level, photos: photoLevel)
            if encodedSize(fitted, text: text) <= limit { return fitted }
        }
        // Still too big with the smallest pictures: the bake-history photos go.
        fitted.recipes = fitted.recipes.map { recipe in
            var recipe = recipe
            recipe.bakeHistory = recipe.bakeHistory?.map { entry in
                var entry = entry
                entry.images = []
                return entry
            }
            return recipe
        }
        return fitted
    }

    /// The encoded file's size without encoding it: the text once, every
    /// picture as the Base64 the encoder writes, plus its key and quotes.
    /// Encoding a 47 MB file pretty-printed takes seconds and twice its
    /// size in memory — too much to do once per level.
    static func encodedSize(_ file: RecipeExportFile, text: Int) -> Int {
        file.recipes.reduce(text) { size, recipe in
            let pictures = [recipe.image].compactMap { $0 } + (recipe.bakeHistory ?? []).flatMap(\.images)
            return pictures.reduce(size) { $0 + base64Length($1) + pictureOverhead }
        }
    }

    /// Indentation, `"image" : ` and the quotes around one picture, generously.
    static let pictureOverhead = 40

    /// The characters the encoder writes for a picture: its Base64, in
    /// which every slash is escaped as `\/`. JPEG data has far more slashes
    /// than one in 64 — its many 0xFF bytes encode to them — so they are
    /// counted rather than guessed.
    static func base64Length(_ data: Data) -> Int {
        autoreleasepool {
            let base64 = data.base64EncodedData()
            return base64.count + base64.count(where: { $0 == UInt8(ascii: "/") })
        }
    }

    /// The size of the file's text: encoded once with every picture taken out.
    static func encodedSizeWithoutPictures(_ file: RecipeExportFile) throws -> Int {
        var bare = file
        bare.recipes = file.recipes.map { recipe in
            var recipe = recipe
            recipe.image = nil
            recipe.bakeHistory = recipe.bakeHistory?.map { entry in
                var entry = entry
                entry.images = []
                return entry
            }
            return recipe
        }
        return try bare.encoded().count
    }

    /// Every recipe picture at `pictures`, every bake-history photo at `photos`.
    static func shrink(_ file: RecipeExportFile,
                       pictures: (edge: CGFloat, quality: CGFloat),
                       photos: (edge: CGFloat, quality: CGFloat)) -> RecipeExportFile {
        var fitted = file
        fitted.recipes = file.recipes.map { recipe in
            var recipe = recipe
            recipe.image = recipe.image.map { BackupPhoto.shrunk($0, longestEdge: pictures.edge, quality: pictures.quality) }
            recipe.bakeHistory = recipe.bakeHistory?.map { entry in
                var entry = entry
                entry.images = entry.images.map { BackupPhoto.shrunk($0, longestEdge: photos.edge, quality: photos.quality) }
                return entry
            }
            return recipe
        }
        return fitted
    }
}
