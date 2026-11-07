//
//  OvenSettings.swift
//  BakePlannerCore
//
//  What the oven is set to for a step, as fields rather than words: the
//  temperature, the one the heat falls to, whether the loaf is steamed. A
//  recipe keeps them with the step (`RecipeExportInstruction.ovenTemperature`,
//  `.ovenFallingTemperature`, `.ovenSteam`); where a step has none, its
//  wording is read as before ("bei 250 °C fallend auf 220 °C mit Schwaden
//  backen"). The plan's generated steps and the bake-day check take the
//  fields first, so a recipe worded loosely still plans exactly.
//

import Foundation

public struct OvenSettings: Equatable, Hashable, Sendable {
    /// Degrees Celsius.
    public var temperature: Int?
    /// The lower temperature the heat is turned down to during the bake.
    public var fallingTo: Int?
    /// True when the bake is steamed, false when the recipe says it is not,
    /// nil when it does not say.
    public var steam: Bool?

    public init(temperature: Int? = nil, fallingTo: Int? = nil, steam: Bool? = nil) {
        self.temperature = temperature
        self.fallingTo = fallingTo
        self.steam = steam
    }

    public var isEmpty: Bool { temperature == nil && fallingTo == nil && steam == nil }

    /// The settings from stored fields; nil when none is set, so a step
    /// without oven data stays nil in every model.
    public static func from(temperature: Int?, fallingTo: Int?, steam: Bool?) -> OvenSettings? {
        let settings = OvenSettings(temperature: temperature, fallingTo: fallingTo, steam: steam)
        return settings.isEmpty ? nil : settings
    }

    /// "250 °C", as the generated oven step writes it.
    public var temperatureText: String? { temperature.map(Self.text) }
    public var fallingText: String? { fallingTo.map(Self.text) }

    public static func text(_ celsius: Int) -> String { "\(celsius) °C" }

    /// "250 °C, fallend auf 220 °C, mit Schwaden" for the recipe pages; nil
    /// when nothing is set.
    public func summary(bundle: Bundle = AppSettings.localizationBundle) -> String? {
        var parts: [String] = []
        if let temperatureText { parts.append(temperatureText) }
        if let fallingText { parts.append(String(localized: "fallend auf \(fallingText)", bundle: bundle)) }
        if let steam {
            parts.append(steam ? String(localized: "mit Schwaden", bundle: bundle)
                               : String(localized: "ohne Schwaden", bundle: bundle))
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
