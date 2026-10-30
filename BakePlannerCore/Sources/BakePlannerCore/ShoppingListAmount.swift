//
//  ShoppingListAmount.swift
//  BakePlannerCore
//

import Foundation

/// Turns a recipe amount into the amount you actually buy.
///
/// A recipe may call for "120 g Eier" — correct for the dough, useless at the
/// counter, where eggs come by the piece. Entries like that are converted once,
/// when they go onto the shopping list; the recipe itself keeps its weight.
public enum ShoppingListAmount {

    /// Unit written on the shopping list for something counted in pieces.
    public static let pieceUnit = "St"

    /// What one entry looks like on the shopping list.
    public struct Amount {
        public var weight: Double
        public var unit: String
        public var num: Int
        public var denom: Int

        public init(weight: Double, unit: String, num: Int, denom: Int) {
            self.weight = weight
            self.unit = unit
            self.num = num
            self.denom = denom
        }
    }

    /// Ingredients that are bought by the piece, with the weight of one piece
    /// in grams as a fallback for recipes that state them by weight. The weight
    /// is only consulted when the recipe does not already count them.
    private static let countedIngredients: [(pattern: String, gramsPerPiece: Double)] = [
        (#"\b(ei|eier|egg|eggs|oeuf|oeufs|œuf|œufs)\b"#, 60)
    ]

    // MARK: - What is not bought

    /// Water: the word itself and the baker's compounds for it, in the three
    /// languages. Not every "…wasser" — rose water is bought.
    private static let waterExpression = try? NSRegularExpression(
        pattern: #"\b(?:schutt|teig|bruh|koch|quell|misch)?wasser\b|\bwater\b|\beau\b"#)
    /// Salt, including "Meersalz"; not "salted butter", and not "Sellerie".
    private static let saltExpression = try? NSRegularExpression(
        pattern: #"salz\b|\bsalt\b|\bsel\b|\bsale\b"#)

    /// Whether an ingredient is something one buys. Water comes from the
    /// tap, salt is always in the house, and a starter — Anstellgut,
    /// Sauerteig, Lievito Madre, Poolish — is made, not bought. Decided from
    /// the name in any of the app's languages, since a public recipe may be
    /// English or French. Dried sourdough or an extract is bought and stays.
    public static func belongsOnList(name: String) -> Bool {
        let key = IngredientNameNormalizer.comparisonKey(name)
        guard !key.isEmpty else { return false }

        if case .starter = DoughComposition.classify(name) { return false }

        return !isWater(name) && !isSalt(name)
    }

    /// Whether a row of the component at `componentIndex` stands for another
    /// component of the same recipe — "Gesamte Kartoffeln (gekocht)" in the
    /// main dough, for the component "Kartoffeln (gekocht)". What that
    /// component is made of is already counted, so the row is neither bought
    /// nor summed up. A row naming its own component is that component's raw
    /// ingredient: "104 g Kartoffeln" under "Kartoffeln (gekocht)" is bought.
    public static func standsForAnotherComponent(name: String,
                                          weight: Double,
                                          num: Int,
                                          denom: Int,
                                          componentIndex: Int,
                                          componentNames: [String]) -> Bool {
        guard let referenced = ComponentProductMatcher.referencedComponent(
            name: name,
            weight: weight,
            numerator: num,
            denominator: denom,
            componentNames: componentNames
        ) else { return false }
        return referenced != componentIndex
    }

    /// Whether the ingredient is water, in any of the app's languages. Shared
    /// with the total ingredients, which leave water out as well.
    public static func isWater(_ name: String) -> Bool {
        matches(waterExpression, name)
    }

    /// Whether the ingredient is salt, in any of the app's languages.
    public static func isSalt(_ name: String) -> Bool {
        matches(saltExpression, name)
    }

    private static func matches(_ expression: NSRegularExpression?, _ name: String) -> Bool {
        let key = IngredientNameNormalizer.comparisonKey(name)
        guard !key.isEmpty else { return false }
        let range = NSRange(key.startIndex..., in: key)
        return expression?.firstMatch(in: key, range: range) != nil
    }

    /// Converts an amount for the shopping list. Anything that is not bought by
    /// the piece is returned unchanged.
    public static func forShoppingList(
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

    /// The amount at the serving scale chosen in the recipe (1.0 is the recipe
    /// as stored), the same way the recipe screens scale their lines.
    ///
    /// A weight simply multiplies. A fraction ("1/2 Würfel Hefe") stays a
    /// fraction as long as the scale is a half step, so it still reads as
    /// "1 Würfel" at ×2; at any other scale it becomes a decimal amount.
    public static func scaled(
        weight: Double,
        num: Int,
        denom: Int,
        by scale: Double
    ) -> (weight: Double, num: Int, denom: Int) {

        guard scale > 0, scale != 1 else { return (weight, num, denom) }

        if weight > 0 {
            return (weight * scale, num, denom)
        }

        guard denom != 0, num != 0 else { return (weight, num, denom) }

        let halfSteps = scale * 2
        let isHalfStep = abs(halfSteps.rounded() - halfSteps) < 0.0001

        guard isHalfStep else {
            return (Double(num) / Double(denom) * scale, 0, 0)
        }

        let scaledNum = num * Int(halfSteps.rounded())
        let scaledDenom = denom * 2
        let divisor = Rational.greatestCommonDivisor(abs(scaledNum), abs(scaledDenom))

        guard divisor != 0 else { return (weight, scaledNum, scaledDenom) }
        return (weight, scaledNum / divisor, scaledDenom / divisor)
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
        if comparableUnit == "ei" || comparableUnit.hasPrefix("ei(") { return true }

        // A unit the user defined as counted rather than weighed. The checks
        // above only know the bundled spellings, so without this a self-made
        // piece unit would be weighed and the shopping list would ask for
        // grams of something you buy by the item.
        return unitSet(for: unit)?.baseUnit == UnitBase.piece.rawValue
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
        let comparableUnit = comparable(UnitLocalizer.canonicalAbbreviation(for: unit) ?? unit)

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
