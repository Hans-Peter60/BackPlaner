//
//  UnitLocalizer.swift
//  BackPlaner
//

import Foundation

/// Units in the language of the app, and units from any language back to the
/// app's own.
///
/// A recipe stores the German abbreviation of a bundled unit ("TL", "Pr",
/// "St"), in Core Data, iCloud and the public database alike, and every
/// calculation (weights, shopping list, scaling) keys on it. That stays so:
/// recipes need no migration, and older app versions keep reading them. Only
/// what the user sees is translated, through the "unit.<abbreviation>…"
/// entries of the string catalog. German shows the stored text unchanged.
///
/// The other way round, imports from English and French pages bring "tsp",
/// "cups" or "c. à s.", which the weight calculation did not know and so read
/// as grams. `normalizeUnits(in:)` turns them into the bundled abbreviation;
/// pounds and ounces become grams, because the bundled "Pfund" is the German
/// 500 g pound and would be 10 % off.
enum UnitLocalizer {

    enum Style {
        /// "tsp", for amounts in lists.
        case abbreviation
        /// "teaspoons", for the unit picker and for reading aloud.
        case name
    }

    // MARK: - Display

    /// The stored unit as the app's language shows it, for `amount` of it.
    /// A unit the app does not ship (a custom or a free-text one) comes back
    /// unchanged.
    static func display(_ unit: String,
                        amount: Double = 1,
                        style: Style = .abbreviation,
                        language: String = UnitLocalizer.appLanguage,
                        bundle: Bundle = AppSettings.localizationBundle) -> String {
        let trimmed = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let abbreviation = bundledAbbreviation(matching: trimmed) else { return unit }

        // German is the language the units are stored in; keep exactly what
        // the recipe says, as before.
        if language.hasPrefix("de") && style == .abbreviation { return trimmed }

        let base = "unit.\(abbreviation)" + (style == .name ? ".name" : "")
        let plural = isPlural(amount, language: language)
        let fallback = bundle.localizedString(forKey: base, value: style == .name ? germanName(of: abbreviation) : abbreviation, table: nil)
        guard plural else { return fallback }
        return bundle.localizedString(forKey: base + ".plural", value: fallback, table: nil)
    }

    /// "tsp – teaspoon": the line the unit picker offers for a unit.
    static func menuTitle(for unitSet: UnitSetFB,
                          language: String = UnitLocalizer.appLanguage,
                          bundle: Bundle = AppSettings.localizationBundle) -> String {
        // A custom unit is the user's own wording in every language.
        guard GlobalVariables.bundledUnitSets.contains(where: { $0.abbreviation == unitSet.abbreviation }) else {
            return "\(unitSet.abbreviation) - \(unitSet.name)"
        }
        let abbreviation = display(unitSet.abbreviation, language: language, bundle: bundle)
        let name = display(unitSet.abbreviation, style: .name, language: language, bundle: bundle)
        return "\(abbreviation) - \(name)"
    }

    /// The language the app shows: the one picked in Settings, or the
    /// system's choice among the app's localizations.
    static var appLanguage: String {
        let stored = AppSettings.storedLanguage
        return stored.isEmpty ? (Bundle.main.preferredLocalizations.first ?? "de") : stored
    }

    /// English uses the plural for anything above one, French from two on.
    private static func isPlural(_ amount: Double, language: String) -> Bool {
        language.hasPrefix("fr") ? amount >= 2 : amount > 1
    }

    private static func germanName(of abbreviation: String) -> String {
        GlobalVariables.bundledUnitSets.first { $0.abbreviation == abbreviation }?.name ?? abbreviation
    }

    /// The bundled abbreviation a stored unit stands for. Recipes store the
    /// abbreviation, but some older ones hold the German name ("Gramm").
    private static func bundledAbbreviation(matching unit: String) -> String? {
        let key = unit.lowercased()
        guard !key.isEmpty else { return nil }
        return GlobalVariables.bundledUnitSets.first {
            $0.abbreviation.lowercased() == key || $0.name.lowercased() == key
        }?.abbreviation
    }

    // MARK: - Recognition

    /// The bundled abbreviation for a unit written in German, English or
    /// French, or nil when it is none the app ships.
    static func canonicalAbbreviation(for unit: String) -> String? {
        let key = comparable(unit)
        guard !key.isEmpty else { return nil }
        if let direct = bundledAbbreviation(matching: unit.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return direct
        }
        return aliases[key]
    }

    /// Spellings the imports meet, by bundled abbreviation. The abbreviation
    /// and the German name of every bundled unit are recognised anyway.
    private static let aliasTable: [String: [String]] = [
        "g":        ["gram", "grams", "gramme", "grammes", "gr", "grs"],
        "kg":       ["kilogram", "kilograms", "kilogramme", "kilogrammes", "kilo", "kilos"],
        "mg":       ["milligram", "milligrams", "milligramme", "milligrammes"],
        "ml":       ["milliliter", "milliliters", "millilitre", "millilitres", "mls"],
        "cl":       ["centiliter", "centiliters", "centilitre", "centilitres"],
        "dl":       ["deciliter", "deciliters", "decilitre", "decilitres", "décilitre", "décilitres"],
        "l":        ["liter", "liters", "litre", "litres", "ltr", "lt"],
        "Pr":       ["prisen", "pinch", "pinches", "pincée", "pincées", "pincee", "pincees"],
        "Msp":      ["messerspitzen", "knife tip", "knife tips", "pointe de couteau", "pointes de couteau"],
        "Bd":       ["bunch", "bunches", "botte", "bottes"],
        "Sc":       ["scheiben", "slice", "slices", "tranche", "tranches"],
        "Rolle":    ["rollen", "roll", "rolls", "rouleau", "rouleaux"],
        // Not "Packung" or "package": a pack of quark is no 11 g sachet.
        "Pck":      ["pck", "packet", "packets", "sachet", "sachets", "pkt"],
        "Handvoll": ["handful", "handfuls", "poignée", "poignées", "poignee", "poignees"],
        "St":       ["stk", "stck", "stück", "stueck", "piece", "pieces", "pc", "pcs", "pce", "pces",
                     "pièce", "pièces", "piece(s)"],
        "ei":       ["eier", "egg", "eggs", "œuf", "œufs", "oeuf", "oeufs"],
        "Tr":       ["drop", "drops", "goutte", "gouttes"],
        "Sp":       ["dash", "dashes", "trait", "traits"],
        "Ss":       ["splash", "splashes", "giclée", "giclées"],
        "TL":       ["tsp", "tsps", "teaspoon", "teaspoons", "c à c", "càc", "cac", "cuillère à café",
                     "cuillères à café", "cuillere a cafe", "cuil à café", "cuill à café"],
        "EL":       ["tbsp", "tbsps", "tbs", "tablespoon", "tablespoons", "c à s", "càs", "cas",
                     "cuillère à soupe", "cuillères à soupe", "cuillere a soupe", "cuil à soupe",
                     "cuill à soupe"],
        "Tas":      ["tassen", "cup", "cups", "tasses"],
    ]

    private static let aliases: [String: String] = {
        var map: [String: String] = [:]
        for (abbreviation, spellings) in aliasTable {
            for spelling in spellings { map[comparable(spelling)] = abbreviation }
        }
        return map
    }()

    /// Lower case, without dots, with single spaces: "C. à s." and "c à s"
    /// are the same unit.
    private static func comparable(_ unit: String) -> String {
        unit.lowercased()
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    // MARK: - Imports

    private static let gramsPerUnit: [String: Double] = [
        "lb": 453.592, "lbs": 453.592, "pound": 453.592, "pounds": 453.592,
        "oz": 28.3495, "ozs": 28.3495, "ounce": 28.3495, "ounces": 28.3495,
    ]

    /// Gives every ingredient of an imported recipe the unit the app knows:
    /// the bundled abbreviation where the spelling is a known one, grams for
    /// pounds and ounces, anything else left as it came.
    static func normalizeUnits(in recipe: RecipeFB) {
        for component in recipe.components {
            for ingredient in component.ingredients {
                normalize(ingredient)
            }
        }
    }

    static func normalize(_ ingredient: IngredientFB) {
        let unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unit.isEmpty else { return }

        if let grams = gramsPerUnit[comparable(unit)] {
            let amount: Double
            if ingredient.weight > 0 {
                amount = ingredient.weight
            } else if ingredient.denom != 0 {
                amount = Double(ingredient.num) / Double(ingredient.denom)
            } else {
                return
            }
            ingredient.weight = (amount * grams).rounded()
            ingredient.num = 0
            ingredient.denom = 0
            ingredient.unit = "g"
            return
        }

        if let abbreviation = canonicalAbbreviation(for: unit) {
            ingredient.unit = abbreviation
        }
    }
}
