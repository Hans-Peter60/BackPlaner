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
    /// (`RecipeExportData.bakeHistory`, `.starterFeedings`); version 3 the
    /// variants (`variantOf`, `variantNote`) and the rating of a bake
    /// (`RecipeExportBakeEntry.rating`); version 4 the room temperature of
    /// a feeding (`RecipeExportStarterFeeding.roomTemperature`); version 5
    /// the duration window of a step (`RecipeExportInstruction.minDuration`,
    /// `.maxDuration`); version 6 the oven settings of a step
    /// (`RecipeExportInstruction.ovenTemperature`, `.ovenFallingTemperature`,
    /// `.ovenSteam`); version 7 the pantry (`RecipeExportFile.pantry`).
    public static let currentFormatVersion = 7
    /// The version of a file with oven settings but without a pantry, as
    /// apps up to 2.4 (20) write and read it.
    public static let ovenFormatVersion = 6
    /// The version of a file with step windows but without oven settings,
    /// as apps up to 2.3 (17) write and read it.
    public static let windowFormatVersion = 5
    /// The version of a file with feeding temperatures but without step
    /// windows, as apps up to 2.3 (15) write and read it.
    public static let feedingTemperatureFormatVersion = 4
    /// The version of a file with variants and ratings but without feeding
    /// temperatures, as apps up to 2.3 (12) write and read it.
    public static let variantFormatVersion = 3
    /// The version of a file with bake history and feedings but without
    /// variants or ratings, as apps up to 2.2 write and read it.
    public static let historyFormatVersion = 2
    /// The version of a file without bake history: unchanged since the
    /// first version, so an older app still reads such a file — a recipe
    /// shared with someone else, for instance.
    public static let plainFormatVersion = 1

    public var formatVersion: Int = Self.currentFormatVersion
    public var recipes: [RecipeExportData]
    /// What is in the house, in a full backup (format version 7): the
    /// pantry is not tied to a recipe, so it stands beside them. Absent in
    /// a shared recipe and in files of older versions.
    public var pantry: [RecipeExportPantryItem]?

    /// Whether this app version knows how to read a file written at
    /// `formatVersion` — a later version may have added fields this one
    /// would silently drop, so only versions up to its own are accepted.
    public static func isSupported(formatVersion: Int) -> Bool {
        formatVersion <= currentFormatVersion
    }

    /// A file of `recipes`, at the lowest version that holds them: 7 when
    /// the file carries a pantry, 6 when a step has oven settings, 5 when a
    /// step has a duration window, 4 when a feeding notes its temperature,
    /// 3 when a recipe is a variant or a bake carries a rating, 2 when a
    /// recipe carries bake history or feedings, 1 otherwise. An older app
    /// refuses a newer file instead of dropping what it does not know
    /// unnoticed.
    public init(formatVersion: Int? = nil, recipes: [RecipeExportData], pantry: [RecipeExportPantryItem]? = nil) {
        self.pantry = (pantry?.isEmpty ?? true) ? nil : pantry
        self.formatVersion = formatVersion ?? Self.lowestVersion(holding: recipes, pantry: self.pantry)
        self.recipes = recipes
    }

    static func lowestVersion(holding recipes: [RecipeExportData], pantry: [RecipeExportPantryItem]? = nil) -> Int {
        if let pantry, !pantry.isEmpty {
            return currentFormatVersion
        }
        if recipes.contains(where: { $0.instructions.contains { $0.oven != nil } }) {
            return ovenFormatVersion
        }
        if recipes.contains(where: { $0.instructions.contains { $0.minDuration != nil || $0.maxDuration != nil } }) {
            return windowFormatVersion
        }
        if recipes.contains(where: { ($0.starterFeedings ?? []).contains { $0.roomTemperature != nil } }) {
            return feedingTemperatureFormatVersion
        }
        if recipes.contains(where: { $0.variantOf != nil || $0.variantNote != nil
                                     || ($0.bakeHistory ?? []).contains { $0.rating != nil } }) {
            return variantFormatVersion
        }
        if recipes.contains(where: { $0.bakeHistory != nil || $0.starterFeedings != nil }) {
            return historyFormatVersion
        }
        return plainFormatVersion
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
    /// The name of the recipe this one is a variant of (format version 3),
    /// nil for a recipe of its own. A name, not a key: keys mean nothing
    /// on another device; reading the file links the variant to the recipe
    /// of that name in the same file, else to one already on the device.
    public var variantOf: String?
    /// What the variant changes, in the baker's words (format version 3).
    public var variantNote: String?

    public init(name: String, summary: String, urlLink: String? = nil, prepTime: Int, totalWeight: Double, tags: [String], rating: Int, recurrenceIntervalDays: Int, image: Data? = nil, components: [RecipeExportComponent], instructions: [RecipeExportInstruction], bakeHistory: [RecipeExportBakeEntry]? = nil, starterFeedings: [RecipeExportStarterFeeding]? = nil, variantOf: String? = nil, variantNote: String? = nil) {
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
        self.variantOf = variantOf
        self.variantNote = variantNote
    }
}

/// One feeding of a starter in a backup file (format version 2; the room
/// temperature since version 4). Values not measured are left out; a failed
/// float test is `false`.
public struct RecipeExportStarterFeeding: Codable, Equatable {
    /// Seconds since 2001, as JSONEncoder writes a Date by default.
    public var date: Date
    public var peakMinutes: Int?
    public var floatTestPassed: Bool?
    public var note: String?
    public var roomTemperature: Double?

    public init(date: Date, facts: StarterFeedingFacts) {
        let facts = facts.normalized
        self.date = date
        peakMinutes = facts.peakMinutes
        floatTestPassed = facts.floatTestPassed
        note = facts.note.isEmpty ? nil : facts.note
        roomTemperature = facts.roomTemperature
    }

    public var facts: StarterFeedingFacts {
        StarterFeedingFacts(peakMinutes: peakMinutes, floatTestPassed: floatTestPassed, note: note ?? "",
                            roomTemperature: roomTemperature).normalized
    }
}

/// One item of the pantry in a backup file (format version 7).
public struct RecipeExportPantryItem: Codable, Equatable {
    public var name: String
    public var amount: Double
    /// "g", "kg" or "St" (`PantryUnit.rawValue`).
    public var unit: String
    /// Seconds since 2001, as JSONEncoder writes a Date by default.
    public var bestBefore: Date?
    /// Left out when empty.
    public var note: String?

    public init(name: String, amount: Double, unit: String, bestBefore: Date? = nil, note: String? = nil) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.bestBefore = bestBefore
        self.note = (note?.isEmpty ?? true) ? nil : note
    }

    public init(_ item: StoredPantryItem) {
        self.init(name: item.name, amount: item.amount, unit: item.unit.rawValue, bestBefore: item.bestBefore, note: item.note)
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
    /// 1 to 5 stars for this bake (format version 3); left out when not rated.
    public var rating: Int?

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
        rating = facts.rating
    }

    public var facts: BakeHistoryFacts {
        BakeHistoryFacts(roomTemperature: roomTemperature, doughTemperature: doughTemperature,
                         bulkProofMinutes: bulkProofMinutes, finalProofMinutes: finalProofMinutes,
                         flour: flour ?? "", outcome: outcome ?? "", rating: rating).normalized
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
    /// The shortest and the longest the step may take, in minutes, when the
    /// recipe gives a window ("12–18 Stunden im Kühlschrank"); the plan may
    /// stretch or shorten the step within it. Both nil without a window
    /// (format version 5; left out of the file when nil).
    public var minDuration: Int?
    public var maxDuration: Int?
    /// The oven's settings for the step as fields (format version 6; left
    /// out of the file when nil): degrees Celsius, the temperature the heat
    /// falls to, whether the bake is steamed. `oven` reads and writes them
    /// as one value.
    public var ovenTemperature: Int?
    public var ovenFallingTemperature: Int?
    public var ovenSteam: Bool?

    public init(instruction: String, step: Double, duration: Int, startTime: Int, bakeFlag: Bool,
                componentName: String? = nil, minDuration: Int? = nil, maxDuration: Int? = nil,
                oven: OvenSettings? = nil) {
        self.instruction = instruction
        self.step = step
        self.duration = duration
        self.startTime = startTime
        self.bakeFlag = bakeFlag
        self.componentName = componentName
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.oven = oven
    }

    /// The oven settings, nil when none is set; setting nil clears all three.
    public var oven: OvenSettings? {
        get { OvenSettings.from(temperature: ovenTemperature, fallingTo: ovenFallingTemperature, steam: ovenSteam) }
        set {
            ovenTemperature = newValue?.temperature
            ovenFallingTemperature = newValue?.fallingTo
            ovenSteam = newValue?.steam
        }
    }

    /// The window as a range, when both bounds are there and the window
    /// has a width; setting nil clears both.
    public var durationWindow: ClosedRange<Int>? {
        get { DurationWindow.range(minimum: minDuration, maximum: maxDuration) }
        set {
            minDuration = newValue?.lowerBound
            maxDuration = newValue?.upperBound
        }
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
