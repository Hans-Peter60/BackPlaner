//
//  ShoppingListAmount.swift
//  BackPlaner
//

import Foundation

/// Turns a recipe amount into the amount you actually buy.
///
/// A recipe may call for "120 g Eier" — correct for the dough, useless at the
/// counter, where eggs come by the piece. Entries like that are converted once,
/// when they go onto the shopping list; the recipe itself keeps its weight.
enum ShoppingListAmount {

    /// Unit written on the shopping list for something counted in pieces.
    static let pieceUnit = "St"

    /// What one entry looks like on the shopping list.
    struct Amount {
        var weight: Double
        var unit: String
        var num: Int
        var denom: Int
    }

    /// Ingredients that are bought by the piece, with the weight of one piece
    /// in grams as a fallback for recipes that state them by weight. The weight
    /// is only consulted when the recipe does not already count them.
    private static let countedIngredients: [(pattern: String, gramsPerPiece: Double)] = [
        (#"\b(ei|eier)\b"#, 60)
    ]

    /// Converts an amount for the shopping list. Anything that is not bought by
    /// the piece is returned unchanged.
    static func forShoppingList(
        name: String,
        unit: String,
        weight: Double,
        num: Int,
        denom: Int
    ) -> Amount {

        let unchanged = Amount(weight: weight, unit: unit, num: num, denom: denom)

        guard let counted = countedIngredient(for: name) else { return unchanged }

        // The recipe may state the amount as a number, as a fraction, or both.
        let statedAmount: Double
        if weight > 0 {
            statedAmount = weight
        } else if denom != 0 {
            statedAmount = Double(num) / Double(denom)
        } else {
            return unchanged
        }

        let pieces: Double
        if isPieceUnit(unit) {
            // Already counted — "4 ei(m)" means four eggs, not four grams.
            pieces = statedAmount
        } else if isGramUnit(unit) {
            pieces = statedAmount / gramsPerPiece(of: unit, fallback: counted.gramsPerPiece)
        } else {
            return unchanged
        }

        // You cannot buy 2.4 eggs, so round up — never down, or the dough is
        // short of an egg.
        let wholePieces = max(1.0, pieces.rounded(.up))

        return Amount(weight: wholePieces, unit: pieceUnit, num: 0, denom: 0)
    }

    private static func countedIngredient(for name: String) -> (pattern: String, gramsPerPiece: Double)? {
        let comparableName = IngredientNameNormalizer.comparisonKey(name)

        return countedIngredients.first { counted in
            comparableName.range(of: counted.pattern, options: [.regularExpression]) != nil
        }
    }

    /// True for the units that already count pieces: "St" and the egg units,
    /// whose amount is a number of eggs rather than a weight.
    private static func isPieceUnit(_ unit: String) -> Bool {
        let comparableUnit = comparable(unit)
        guard !comparableUnit.isEmpty else { return false }

        if comparableUnit == comparable(pieceUnit) || comparableUnit.hasPrefix("stuck") { return true }
        return comparableUnit == "ei" || comparableUnit.hasPrefix("ei(")
    }

    private static func isGramUnit(_ unit: String) -> Bool {
        let comparableUnit = comparable(unit)
        guard !comparableUnit.isEmpty else { return false }

        return unitSet(for: unit)?.baseUnit == "g" && !isPieceUnit(unit)
    }

    /// Weight of one piece. An egg unit carries it already (Ei(l) is 70 g), so
    /// that value is preferred over the fallback.
    private static func gramsPerPiece(of unit: String, fallback: Double) -> Double {
        guard let matching = GlobalVariables.unitSets.first(where: {
            comparable($0.name) == "ei" || comparable($0.abbreviation) == "ei"
        }), matching.factor > 0 else {
            return fallback
        }
        return matching.factor
    }

    private static func unitSet(for unit: String) -> UnitSetFB? {
        let comparableUnit = comparable(unit)

        return GlobalVariables.unitSets.first { unitSet in
            comparableUnit == comparable(unitSet.abbreviation) || comparableUnit == comparable(unitSet.name)
        }
    }

    private static func comparable(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .localizedLowercase
    }
}
