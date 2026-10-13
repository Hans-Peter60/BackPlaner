//
//  RecipeExport.swift
//  BackPlaner
//
//  A recipe (or several) as a self-contained JSON file: everything needed to
//  recreate it on another device or hand it to someone else without putting
//  it in the public database — the one thing the manual still lists as
//  missing. Bake history and the starter feeding diary are left out
//  deliberately: those are this device's record of what actually happened,
//  not part of the recipe itself, the same boundary "Rezept veröffentlichen"
//  already draws for the public database.
//

import Foundation
import CoreData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - File format

struct RecipeExportFile: Codable, Equatable {
    static let currentFormatVersion = 1

    var formatVersion: Int = Self.currentFormatVersion
    var recipes: [RecipeExportData]

    /// Whether this app version knows how to read a file written at
    /// `formatVersion` — a later version may have added fields this one
    /// would silently drop, so only versions up to its own are accepted.
    static func isSupported(formatVersion: Int) -> Bool {
        formatVersion <= currentFormatVersion
    }
}

struct RecipeExportData: Codable, Equatable {
    var name: String
    var summary: String
    var urlLink: String?
    var prepTime: Int
    var totalWeight: Double
    var tags: [String]
    var rating: Int
    var recurrenceIntervalDays: Int
    /// JSON encodes `Data` as base64 on its own, so the image travels inline
    /// with no extra work here.
    var image: Data?
    var components: [RecipeExportComponent]
    var instructions: [RecipeExportInstruction]
}

struct RecipeExportComponent: Codable, Equatable {
    var name: String
    var number: Int
    var ingredients: [RecipeExportIngredient]
}

struct RecipeExportIngredient: Codable, Equatable {
    var name: String
    var number: Int
    var unit: String?
    var weight: Double
    var normWeight: Double
    var num: Int
    var denom: Int
}

struct RecipeExportInstruction: Codable, Equatable {
    var instruction: String
    var step: Double
    var duration: Int
    var startTime: Int
    var bakeFlag: Bool
    var componentName: String?
}

// MARK: - Recipe → export data

extension RecipeExportData {
    init(recipe: Recipe) {
        name                   = recipe.name
        summary                = recipe.summary
        urlLink                = recipe.urlLink
        prepTime               = recipe.prepTime
        totalWeight            = recipe.totalWeight
        tags                   = recipe.tags
        rating                 = recipe.rating
        recurrenceIntervalDays = recipe.recurrenceIntervalDays
        image                  = recipe.image.isEmpty ? nil : recipe.image

        components = recipe.componentsArray.map { component in
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
        }

        instructions = recipe.instructionsArray.map { instruction in
            RecipeExportInstruction(
                instruction: instruction.instruction,
                step: instruction.step,
                duration: instruction.duration,
                startTime: instruction.startTime,
                bakeFlag: instruction.bakeFlag,
                componentName: instruction.componentName
            )
        }
    }
}

extension RecipeExportData {
    /// A recipe from the public database, with its picture from the download
    /// cache. Components, ingredients and steps are put in their display
    /// order, so an index into `ComponentColumn.columns(of:)` lands on the
    /// same line here.
    init(recipeFB: RecipeFB, image: UIImage?) {
        name                   = recipeFB.name
        summary                = recipeFB.summary
        urlLink                = recipeFB.urlLink.isEmpty ? nil : recipeFB.urlLink
        prepTime               = recipeFB.prepTime
        totalWeight            = recipeFB.totalWeight
        tags                   = recipeFB.tags
        rating                 = recipeFB.rating
        recurrenceIntervalDays = 0
        self.image             = image?.jpegData(compressionQuality: 1.0)

        components = recipeFB.components
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
            }

        instructions = recipeFB.instructions
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
    let file: RecipeExportFile
    let fileName: String

    init(recipe: Recipe) {
        file = RecipeExportFile(recipes: [RecipeExportData(recipe: recipe)])
        fileName = Self.sanitizedFileName(recipe.name.isEmpty ? "Rezept" : recipe.name)
    }

    init(recipes: [Recipe], fileName: String) {
        file = RecipeExportFile(recipes: recipes.map(RecipeExportData.init))
        self.fileName = Self.sanitizedFileName(fileName)
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
            .appendingPathExtension("json")
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Import

enum RecipeImportError: LocalizedError {
    case unreadableFile
    case unsupportedFormatVersion

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return String(localized: "Die Datei ist keine gültige BakePlanner-Rezeptdatei.", bundle: AppSettings.localizationBundle)
        case .unsupportedFormatVersion:
            return String(localized: "Diese Datei wurde mit einer neueren Version von BakePlanner erstellt. Bitte aktualisiere die App.", bundle: AppSettings.localizationBundle)
        }
    }
}

enum RecipeImport {
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

        let file: RecipeExportFile
        do {
            file = try JSONDecoder().decode(RecipeExportFile.self, from: data)
        } catch {
            throw RecipeImportError.unreadableFile
        }

        guard RecipeExportFile.isSupported(formatVersion: file.formatVersion) else {
            throw RecipeImportError.unsupportedFormatVersion
        }

        for recipeData in file.recipes {
            _ = recipeData.makeRecipe(in: context)
        }

        try context.save()
        return file.recipes.count
    }
}
