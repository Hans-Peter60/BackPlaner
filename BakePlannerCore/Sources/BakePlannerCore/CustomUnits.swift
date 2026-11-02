//
//  CustomUnits.swift
//  BakePlannerCore
//
//  Units the user defines on top of the 28 the app ships with: what one is,
//  what makes a new one valid, and how they join the unit table the
//  weight calculation reads. Moved from the iOS app (CustomUnitStore in
//  AppSettings.swift) so Android keeps the same units the same way; where
//  they are stored stays with each app.
//

import Foundation

/// A unit the user defined himself, on top of the ones the app ships with.
/// Encoded as the iPhone has stored it since the units were introduced.
public struct CustomUnit: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    public var abbreviation: String
    public var factor: Double
    public var baseUnit: String

    public init(id: UUID = UUID(), name: String, abbreviation: String, factor: Double, baseUnit: String) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.factor = factor
        self.baseUnit = baseUnit
    }

    public var base: UnitBase { UnitBase(rawValue: baseUnit) ?? .gram }
}

/// Why a unit could not be added. The apps word these.
public enum CustomUnitError: Error, Equatable, Sendable {
    case missingName
    case missingAbbreviation
    case factorNotPositive
    case abbreviationTaken(String)
}

public enum CustomUnits {

    /// The unit the input describes, or why it is no unit yet: a name and an
    /// abbreviation, a factor above zero (a counted unit's is always 1), and
    /// neither name nor abbreviation already in use — units are looked up by
    /// either, so a clash on one would make a unit unreachable.
    public static func validated(name: String, abbreviation: String, factor: Double?, base: UnitBase,
                                 existing: [CustomUnit]) throws -> CustomUnit {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAbbreviation = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanName.isEmpty else { throw CustomUnitError.missingName }
        guard !cleanAbbreviation.isEmpty else { throw CustomUnitError.missingAbbreviation }

        let effectiveFactor = base == .piece ? 1 : (factor ?? 0)
        guard effectiveFactor > 0 else { throw CustomUnitError.factorNotPositive }

        guard !isTaken(cleanAbbreviation, among: existing), !isTaken(cleanName, among: existing) else {
            throw CustomUnitError.abbreviationTaken(cleanAbbreviation)
        }

        return CustomUnit(name: cleanName, abbreviation: cleanAbbreviation, factor: effectiveFactor, baseUnit: base.rawValue)
    }

    /// True when a bundled unit or one of `units` already answers to this
    /// text, as name or abbreviation, whatever the case or accents.
    public static func isTaken(_ text: String, among units: [CustomUnit]) -> Bool {
        let key = comparable(text)
        guard !key.isEmpty else { return false }
        return GlobalVariables.bundledUnitSets.contains {
            comparable($0.abbreviation) == key || comparable($0.name) == key
        } || units.contains {
            comparable($0.abbreviation) == key || comparable($0.name) == key
        }
    }

    /// The units in the shape the rest of the app reads units in
    /// (`GlobalVariables.customUnitSets`).
    public static func unitSets(_ units: [CustomUnit]) -> [UnitSetFB] {
        units.map { custom in
            let unitSet = UnitSetFB()
            unitSet.id = custom.id.uuidString
            unitSet.name = custom.name
            unitSet.abbreviation = custom.abbreviation
            unitSet.factor = custom.factor
            unitSet.baseUnit = custom.baseUnit
            return unitSet
        }
    }

    /// The units as the apps keep them, JSON; nothing for data that is none.
    public static func decode(_ data: Data) -> [CustomUnit] {
        (try? JSONDecoder().decode([CustomUnit].self, from: data)) ?? []
    }

    public static func encode(_ units: [CustomUnit]) -> Data? {
        try? JSONEncoder().encode(units)
    }

    private static func comparable(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }
}
