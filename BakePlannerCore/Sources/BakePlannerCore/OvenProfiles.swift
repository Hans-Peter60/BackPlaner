//
//  OvenProfiles.swift
//  BakePlannerCore
//
//  The ovens one bakes in, each with what the plan needs to know about it:
//  how long it takes to heat up, with and without a stone, whether it runs
//  hotter or colder than its dial says, and the convection reduction. A
//  BakePlanner Pro feature; without a profile the plan uses the plain
//  settings as before.
//

import Foundation

public struct OvenProfile: Codable, Identifiable, Equatable, Hashable, Sendable {

    public var id: UUID
    public var name: String
    /// Minutes the oven needs before a bake without a stone.
    public var preheatMinutes: Int
    /// Minutes with a baking stone or steel inside.
    public var stonePreheatMinutes: Int
    /// Degrees Celsius the oven runs hotter than its dial says; negative
    /// when it runs colder. The dial is set lower by this amount.
    public var runsHotBy: Int
    /// True when the oven bakes with the fan on, so the dial is set lower
    /// than a recipe's top-and-bottom-heat temperature.
    public var convection: Bool
    /// Degrees Celsius taken off for the fan when `convection` is on.
    public var fanReduction: Int

    public static let defaultFanReduction = 20
    /// The largest deviation the editor offers either way.
    public static let maximumDeviation = 30

    public init(id: UUID = UUID(), name: String,
                preheatMinutes: Int = AppSettings.defaultPreheatTime,
                stonePreheatMinutes: Int = AppSettings.defaultStonePreheatTime,
                runsHotBy: Int = 0, convection: Bool = false,
                fanReduction: Int = OvenProfile.defaultFanReduction) {
        self.id = id
        self.name = name
        self.preheatMinutes = preheatMinutes
        self.stonePreheatMinutes = stonePreheatMinutes
        self.runsHotBy = runsHotBy
        self.convection = convection
        self.fanReduction = fanReduction
    }

    /// Degrees Celsius the dial is set below a recipe's temperature.
    public var correction: Int {
        runsHotBy + (convection ? fanReduction : 0)
    }

    /// Whether the dial differs from the recipe at all.
    public var hasCorrection: Bool { correction != 0 }

    /// What to set the dial to for a recipe temperature, never below 50 °C.
    public func dialTemperature(for celsius: Int) -> Int {
        max(50, celsius - correction)
    }

    /// "am Regler 240 °C" for a recipe temperature, in the plan's language;
    /// nil when the dial matches the recipe.
    public func dialNote(for celsius: Int, languageCode: String) -> String? {
        guard hasCorrection else { return nil }
        let format = AppSettings.generatedStepTexts(languageCode: languageCode).dial
        return String(format: format, OvenSettings.text(dialTemperature(for: celsius)))
    }

    /// The dial note for a step's wording, for the bake mode: nil when the
    /// step names no Celsius oven temperature, when the dial matches, or
    /// when the text carries the note already (a generated oven step).
    public func dialNote(forInstruction instruction: String, languageCode: String) -> String? {
        guard let celsius = BakePlan.ovenTemperatureCelsius(in: instruction),
              let note = dialNote(for: celsius, languageCode: languageCode),
              !instruction.contains(note) else { return nil }
        return note
    }
}

public enum OvenProfiles {

    /// The profiles as stored: a JSON array under one settings key, so they
    /// travel with the other settings (iCloud on iOS, the settings file on
    /// Android).
    public static func decode(_ json: String?) -> [OvenProfile] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([OvenProfile].self, from: data)) ?? []
    }

    public static func encode(_ profiles: [OvenProfile]) -> String {
        guard let data = try? JSONEncoder().encode(profiles) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The oven the plan works with: the chosen one, else the first; nil
    /// without profiles.
    public static func selected(from profiles: [OvenProfile], selectedID: String?) -> OvenProfile? {
        if let selectedID, let uuid = UUID(uuidString: selectedID),
           let chosen = profiles.first(where: { $0.id == uuid }) {
            return chosen
        }
        return profiles.first
    }

    /// The stored profiles.
    public static var stored: [OvenProfile] {
        decode(AppSettings.storedString(forKey: AppSettingsKeys.ovenProfiles))
    }

    /// The stored oven the plan works with, if there is one.
    public static var selected: OvenProfile? {
        selected(from: stored, selectedID: AppSettings.storedString(forKey: AppSettingsKeys.selectedOvenProfile))
    }
}
