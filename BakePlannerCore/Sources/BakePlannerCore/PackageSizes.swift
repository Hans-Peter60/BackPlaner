//
//  PackageSizes.swift
//  BakePlannerCore
//
//  What the shop sells. A recipe needs 200 g of flour, but nobody buys
//  200 g: the shopping list names the package one actually buys, and the
//  pantry intake starts from that package rather than from the recipe's
//  amount.
//

import Foundation

public enum PackageSizes {

    /// The package to buy for a needed amount, in grams or pieces: the
    /// smallest standard package that covers the need, or as many of the
    /// largest as fit plus one that covers the rest. Nil when nothing
    /// standard exists for the ingredient — liquids, spices, fruit, things
    /// unknown — or when the need is counted but the packages are weighed
    /// (or the other way round); the line then stays as the recipe puts it.
    public static func package(name: String, amount: Double, unit: PantryUnit) -> (amount: Double, unit: PantryUnit)? {
        guard amount > 0, let sizes = sizes(for: name) else { return nil }
        let counted = unit == .piece
        guard counted == sizes.counted else { return nil }
        let need = counted ? amount : amount * (unit.grams ?? 1)
        let bought = covering(need, sizes: sizes.amounts)
        if counted { return (bought, .piece) }
        // Big packages are kept in kilograms, as the pantry shows them.
        return bought >= 1_000 ? (bought / 1_000, .kilogram) : (bought, .gram)
    }

    /// Whether the package differs from the need, i.e. whether the line
    /// should tell both.
    public static func differs(_ package: (amount: Double, unit: PantryUnit), from amount: Double, unit: PantryUnit) -> Bool {
        if package.unit == .piece || unit == .piece {
            return package.unit != unit || abs(package.amount - amount) > 0.001
        }
        return abs(package.amount * (package.unit.grams ?? 1) - amount * (unit.grams ?? 1)) > 0.001
    }

    /// The smallest size covering the need; above the largest size, whole
    /// large packages plus one that covers the rest.
    static func covering(_ need: Double, sizes: [Double]) -> Double {
        let sizes = sizes.sorted()
        guard let largest = sizes.last, need > 0 else { return 0 }
        if let fit = sizes.first(where: { $0 >= need - 0.001 }) { return fit }
        let packs = (need / largest).rounded(.down)
        let rest = need - packs * largest
        let extra = rest > 0.001 ? (sizes.first { $0 >= rest - 0.001 } ?? largest) : 0
        return packs * largest + extra
    }

    // MARK: Sizes

    struct Sizes: Equatable {
        /// Grams, or pieces when counted.
        var amounts: [Double]
        var counted = false
    }

    private struct Rule {
        var patterns: [String]
        /// Nil: this ingredient has no standard package.
        var sizes: Sizes?
    }

    /// Names first — "Trockenhefe" before "Hefe", butter before the other
    /// fats — then the shelf decides.
    private static let rules: [Rule] = [
        Rule(patterns: ["trockenhefe", "dry yeast", "instant yeast", "levure seche", "levure boulangere"],
             sizes: Sizes(amounts: [7])),
        Rule(patterns: ["hefe", "yeast", "levure"], sizes: Sizes(amounts: [42])),
        Rule(patterns: ["backpulver", "baking powder", "levure chimique"], sizes: Sizes(amounts: [15])),
        Rule(patterns: ["butter", "beurre"], sizes: Sizes(amounts: [250])),
        Rule(patterns: [#"\bei\b"#, #"\beier\b"#, #"\beggs?\b"#, "oeuf"], sizes: Sizes(amounts: [6, 10], counted: true)),
        // Liquid dairy is bought by the bottle or cup; the pantry keeps grams,
        // so the line stays with the recipe's amount.
        Rule(patterns: ["milch", "milk", "lait", "sahne", "rahm", "cream", "creme", "kefir", "molke", "whey"], sizes: nil),
        Rule(patterns: ["salz", "salt", #"\bsel\b"#, "zucker", "sugar", "sucre"], sizes: Sizes(amounts: [500, 1_000])),
        Rule(patterns: ["honig", "honey", #"\bmiel\b"#, "sirup", "syrup", "sirop", "malz", "malt"],
             sizes: Sizes(amounts: [250, 500])),
    ]

    private static let shelfSizes: [ShoppingListCategory: Sizes] = [
        .flourAndGrain: Sizes(amounts: [500, 1_000, 2_000, 2_500]),
        .nutsSeedsDriedFruit: Sizes(amounts: [100, 200, 500, 1_000]),
        .dairyAndEggs: Sizes(amounts: [250, 500]),
    ]

    static func sizes(for name: String) -> Sizes? {
        let key = IngredientNameNormalizer.comparisonKey(name)
        guard !key.isEmpty else { return nil }
        for rule in rules where rule.patterns.contains(where: { matches(key, $0) }) {
            return rule.sizes
        }
        return shelfSizes[ShoppingListCategory.category(for: name)]
    }

    private static func matches(_ key: String, _ pattern: String) -> Bool {
        if pattern.contains("\\") {
            return key.range(of: pattern, options: [.regularExpression]) != nil
        }
        return key.contains(pattern)
    }
}
