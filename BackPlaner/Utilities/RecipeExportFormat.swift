//
//  RecipeExportFormat.swift
//  BackPlaner
//
//  The recipe file format itself — what a backup or shared recipe file
//  holds, how it is written and read — independent of where the recipes
//  are stored. RecipeExport.swift connects it to Core Data and the share
//  sheet.
//

import Foundation

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

extension RecipeExportFile {
    /// The file's contents as written: readable JSON with sorted keys.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

// MARK: - Reading a file

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
    /// The recipes of a backup/share file, or why it cannot be read: not a
    /// recipe file at all, or one written by a newer version of the app.
    static func decodeFile(_ data: Data) throws -> RecipeExportFile {
        let file: RecipeExportFile
        do {
            file = try JSONDecoder().decode(RecipeExportFile.self, from: data)
        } catch {
            throw RecipeImportError.unreadableFile
        }

        guard RecipeExportFile.isSupported(formatVersion: file.formatVersion) else {
            throw RecipeImportError.unsupportedFormatVersion
        }
        return file
    }
}
