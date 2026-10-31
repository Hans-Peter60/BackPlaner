//
//  RecipeExportFormat.swift
//  BakePlannerCore
//
//  The recipe file format itself — what a backup or shared recipe file
//  holds, how it is written and read — independent of where the recipes
//  are stored. RecipeExport.swift connects it to Core Data and the share
//  sheet.
//

import Foundation

// MARK: - File format

public struct RecipeExportFile: Codable, Equatable {
    /// The newest version this app writes and reads. Version 2 added the
    /// bake history and the starter feeding diary of each recipe
    /// (`RecipeExportData.bakeHistory`, `.starterFeedings`).
    public static let currentFormatVersion = 2
    /// The version of a file without bake history: unchanged since the
    /// first version, so an older app still reads such a file — a recipe
    /// shared with someone else, for instance.
    public static let plainFormatVersion = 1

    public var formatVersion: Int = Self.currentFormatVersion
    public var recipes: [RecipeExportData]

    /// Whether this app version knows how to read a file written at
    /// `formatVersion` — a later version may have added fields this one
    /// would silently drop, so only versions up to its own are accepted.
    public static func isSupported(formatVersion: Int) -> Bool {
        formatVersion <= currentFormatVersion
    }

    /// A file of `recipes`, at the lowest version that holds them: 2 when
    /// a recipe carries bake history or feedings, 1 otherwise. An older app
    /// refuses a version-2 file instead of dropping them unnoticed.
    public init(formatVersion: Int? = nil, recipes: [RecipeExportData]) {
        self.formatVersion = formatVersion
            ?? (recipes.contains { $0.bakeHistory != nil || $0.starterFeedings != nil }
                ? Self.currentFormatVersion : Self.plainFormatVersion)
        self.recipes = recipes
    }
}

public struct RecipeExportData: Codable, Equatable {
    public var name: String
    public var summary: String
    public var urlLink: String?
    public var prepTime: Int
    public var totalWeight: Double
    public var tags: [String]
    public var rating: Int
    public var recurrenceIntervalDays: Int
    /// JSON encodes `Data` as base64 on its own, so the image travels inline
    /// with no extra work here.
    public var image: Data?
    public var components: [RecipeExportComponent]
    public var instructions: [RecipeExportInstruction]
    /// The recipe's bakes, newest first — only in a full backup (format
    /// version 2), nil otherwise and then left out of the file entirely.
    public var bakeHistory: [RecipeExportBakeEntry]?
    /// The starter's feedings, newest first — likewise only in a full
    /// backup, nil otherwise.
    public var starterFeedings: [RecipeExportStarterFeeding]?

    public init(name: String, summary: String, urlLink: String? = nil, prepTime: Int, totalWeight: Double, tags: [String], rating: Int, recurrenceIntervalDays: Int, image: Data? = nil, components: [RecipeExportComponent], instructions: [RecipeExportInstruction], bakeHistory: [RecipeExportBakeEntry]? = nil, starterFeedings: [RecipeExportStarterFeeding]? = nil) {
        self.name = name
        self.summary = summary
        self.urlLink = urlLink
        self.prepTime = prepTime
        self.totalWeight = totalWeight
        self.tags = tags
        self.rating = rating
        self.recurrenceIntervalDays = recurrenceIntervalDays
        self.image = image
        self.components = components
        self.instructions = instructions
        self.bakeHistory = bakeHistory
        self.starterFeedings = starterFeedings
    }
}

/// One feeding of a starter in a backup file (format version 2). Values not
/// measured are left out; a failed float test is `false`.
public struct RecipeExportStarterFeeding: Codable, Equatable {
    /// Seconds since 2001, as JSONEncoder writes a Date by default.
    public var date: Date
    public var peakMinutes: Int?
    public var floatTestPassed: Bool?
    public var note: String?

    public init(date: Date, facts: StarterFeedingFacts) {
        let facts = facts.normalized
        self.date = date
        peakMinutes = facts.peakMinutes
        floatTestPassed = facts.floatTestPassed
        note = facts.note.isEmpty ? nil : facts.note
    }

    public var facts: StarterFeedingFacts {
        StarterFeedingFacts(peakMinutes: peakMinutes, floatTestPassed: floatTestPassed, note: note ?? "").normalized
    }
}

/// One bake of a recipe in a backup file (format version 2). Values not
/// recorded are left out.
public struct RecipeExportBakeEntry: Codable, Equatable {
    /// Seconds since 2001, as JSONEncoder writes a Date by default.
    public var date: Date
    public var comment: String
    /// JPEG photos, base64 in the file.
    public var images: [Data]
    public var roomTemperature: Double?
    public var doughTemperature: Double?
    public var bulkProofMinutes: Int?
    public var finalProofMinutes: Int?
    public var flour: String?
    public var outcome: String?

    public init(date: Date, comment: String, images: [Data], facts: BakeHistoryFacts) {
        let facts = facts.normalized
        self.date = date
        self.comment = comment
        self.images = images
        roomTemperature = facts.roomTemperature
        doughTemperature = facts.doughTemperature
        bulkProofMinutes = facts.bulkProofMinutes
        finalProofMinutes = facts.finalProofMinutes
        flour = facts.flour.isEmpty ? nil : facts.flour
        outcome = facts.outcome.isEmpty ? nil : facts.outcome
    }

    public var facts: BakeHistoryFacts {
        BakeHistoryFacts(roomTemperature: roomTemperature, doughTemperature: doughTemperature,
                         bulkProofMinutes: bulkProofMinutes, finalProofMinutes: finalProofMinutes,
                         flour: flour ?? "", outcome: outcome ?? "").normalized
    }
}

public struct RecipeExportComponent: Codable, Equatable {
    public var name: String
    public var number: Int
    public var ingredients: [RecipeExportIngredient]

    public init(name: String, number: Int, ingredients: [RecipeExportIngredient]) {
        self.name = name
        self.number = number
        self.ingredients = ingredients
    }
}

public struct RecipeExportIngredient: Codable, Equatable {
    public var name: String
    public var number: Int
    public var unit: String?
    public var weight: Double
    public var normWeight: Double
    public var num: Int
    public var denom: Int

    public init(name: String, number: Int, unit: String? = nil, weight: Double, normWeight: Double, num: Int, denom: Int) {
        self.name = name
        self.number = number
        self.unit = unit
        self.weight = weight
        self.normWeight = normWeight
        self.num = num
        self.denom = denom
    }
}

public struct RecipeExportInstruction: Codable, Equatable {
    public var instruction: String
    public var step: Double
    public var duration: Int
    public var startTime: Int
    public var bakeFlag: Bool
    public var componentName: String?

    public init(instruction: String, step: Double, duration: Int, startTime: Int, bakeFlag: Bool, componentName: String? = nil) {
        self.instruction = instruction
        self.step = step
        self.duration = duration
        self.startTime = startTime
        self.bakeFlag = bakeFlag
        self.componentName = componentName
    }
}

extension RecipeExportFile {
    /// The file's contents as written: readable JSON with sorted keys.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

// MARK: - Reading a file

public enum RecipeImportError: LocalizedError {
    case unreadableFile
    case unsupportedFormatVersion

    public var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return String(localized: "Die Datei ist keine gültige BakePlanner-Rezeptdatei.", bundle: AppSettings.localizationBundle)
        case .unsupportedFormatVersion:
            return String(localized: "Diese Datei wurde mit einer neueren Version von BakePlanner erstellt. Bitte aktualisiere die App.", bundle: AppSettings.localizationBundle)
        }
    }
}

public enum RecipeImport {
    /// The recipes of a backup/share file, or why it cannot be read: not a
    /// recipe file at all, or one written by a newer version of the app.
    public static func decodeFile(_ data: Data) throws -> RecipeExportFile {
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
