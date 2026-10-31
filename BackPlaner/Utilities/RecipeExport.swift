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
//  database. The full backup from the settings carries it along (format
//  version 2), so it moves to a new device with the recipes. The starter
//  feeding diary is not in the file.
//

import BakePlannerCore
import Foundation
import CoreData
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
                    componentName: instruction.componentName
                )
            }
        )
    }
}

extension RecipeExportData {
    /// A recipe from the public database, with its picture from the download
    /// cache. Components, ingredients and steps are put in their display
    /// order, so an index into `ComponentColumn.columns(of:)` lands on the
    /// same line here.
    init(recipeFB: RecipeFB, image: UIImage?) {
        // Another module's struct: its own initializer sets the fields.
        self.init(
            name: recipeFB.name,
            summary: recipeFB.summary,
            urlLink: recipeFB.urlLink.isEmpty ? nil : recipeFB.urlLink,
            prepTime: recipeFB.prepTime,
            totalWeight: recipeFB.totalWeight,
            tags: recipeFB.tags,
            rating: recipeFB.rating,
            recurrenceIntervalDays: 0,
            image: image?.jpegData(compressionQuality: 1.0),
            components: recipeFB.components
                .sorted { $0.number < $1.number }
                .map { component in
                    RecipeExportComponent(
                        name: component.name,
                        number: component.number,
                        ingredients: component.ingredients
                            .sorted { $0.number < $1.number }
                            .map { ingredient in
                                RecipeExportIngredient(
                                    name: ingredient.name,
                                    number: ingredient.number,
                                    unit: ingredient.unit.isEmpty ? nil : ingredient.unit,
                                    weight: ingredient.weight,
                                    normWeight: ingredient.normWeight,
                                    num: ingredient.num,
                                    denom: ingredient.denom
                                )
                            }
                    )
                },
            instructions: recipeFB.instructions
                .sorted { $0.step < $1.step }
                .map { instruction in
                    RecipeExportInstruction(
                        instruction: instruction.instruction,
                        step: instruction.step,
                        duration: instruction.duration,
                        startTime: instruction.startTime ?? 0,
                        bakeFlag: instruction.bakeFlag ?? false,
                        componentName: instruction.componentName
                    )
                }
        )
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
            recipe.addToInstructions(instruction)
        }

        return recipe
    }
}

// MARK: - Share sheet item

/// What `ShareLink` hands to the share sheet: one recipe, or — from the
/// settings backup — every recipe on the device, as one file either way.
struct RecipeFileExport: Transferable {
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

    private init(recipes: [Recipe], fileName: String, includesBakeHistory: Bool) {
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
                                                      shrinkPhoto: BackupPhoto.shrunk) {
                    file = backup
                    return
                }
            }
            file = RecipeExportFile(recipes: recipeIDs
                .compactMap { try? context.existingObject(with: $0) as? Recipe }
                .map(RecipeExportData.init))
        }
        return file
    }

    private static func sanitizedFileName(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
            .joined(separator: "-")
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            SentTransferredFile(try export.write())
        }
    }

    private func write() throws -> URL {
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
                              bakeHistory: CoreDataBakeHistoryStore(context: context))
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
        guard let image = UIImage(data: data) else { return data }
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        let longest = max(width, height)
        guard longest > longestEdge else { return data }

        let factor = longestEdge / longest
        let size = CGSize(width: (width * factor).rounded(), height: (height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: jpegQuality) ?? data
    }
}
