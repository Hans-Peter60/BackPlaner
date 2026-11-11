//
//  PantryMatcher.swift
//  BakePlannerCore
//
//  A recipe against the pantry: what of it is in the house, what is
//  missing and how much, what the shopping list may leave out, and what
//  a bake takes out of the pantry. Names meet by the comparison key the
//  shopping list merges with; amounts meet in grams, or in pieces for
//  what is counted (eggs).
//

import Foundation

/// One bought ingredient of a recipe, against the pantry.
public struct PantryNeed: Equatable, Sendable {
    /// The ingredient as the recipe names it, cleaned for display.
    public let name: String
    /// What the recipe needs, in grams or pieces.
    public let requiredBase: Double
    /// What the pantry holds of it, in the same base.
    public let availableBase: Double
    /// Counted (pieces) rather than weighed.
    public let isCounted: Bool

    public init(name: String, requiredBase: Double, availableBase: Double, isCounted: Bool) {
        self.name = name
        self.requiredBase = requiredBase
        self.availableBase = availableBase
        self.isCounted = isCounted
    }

    public var missingBase: Double { max(0, requiredBase - availableBase) }
    /// Covered when the pantry holds at least what is needed (a gram of
    /// rounding does not count as missing).
    public var isCovered: Bool { availableBase + 0.5 >= requiredBase }
}

/// What the pantry says about a recipe.
public struct PantryCheck: Equatable, Sendable {
    public let needs: [PantryNeed]

    public init(needs: [PantryNeed]) { self.needs = needs }

    public var covered: [PantryNeed] { needs.filter(\.isCovered) }
    public var missing: [PantryNeed] { needs.filter { !$0.isCovered } }
    /// Everything the recipe needs is there — and it needs something.
    public var isComplete: Bool { !needs.isEmpty && missing.isEmpty }
}

/// A pantry item that runs out soon, and how much of it a recipe uses.
public struct PantryUse: Equatable, Sendable {
    public let item: StoredPantryItem
    /// Grams or pieces of the item the recipe uses, no more than it holds.
    public let usedBase: Double

    public init(item: StoredPantryItem, usedBase: Double) {
        self.item = item
        self.usedBase = usedBase
    }
}

/// One pantry item after a bake: the amount it keeps.
public struct PantryDeduction: Equatable, Sendable {
    public let item: StoredPantryItem
    /// The amount taken, in the item's unit.
    public let taken: Double

    public init(item: StoredPantryItem, taken: Double) {
        self.item = item
        self.taken = taken
    }

    public var remaining: Double { max(0, item.amount - taken) }
}

public enum PantryMatcher {

    /// The recipe at `scale` against the pantry, one need per ingredient
    /// (the same flour in two components is one need).
    public static func check(_ recipe: RecipeExportData, scale: Double, pantry: [StoredPantryItem]) -> PantryCheck {
        let entries = ShoppingListBuilder.entriesToBuy(ShoppingListBuilder.entries(of: recipe), scale: scale)
        return PantryCheck(needs: needs(of: entries, pantry: pantry))
    }

    /// The shopping-list entries with what the pantry covers taken out:
    /// a covered entry goes, a partly covered one in grams, kilograms or
    /// pieces shrinks to the missing amount, any other unit stays whole.
    public static func reduce(_ entries: [ShoppingListEntry], pantry: [StoredPantryItem]) -> [ShoppingListEntry] {
        guard !pantry.isEmpty else { return entries }
        var remainingByKey: [String: Double] = [:]
        for item in pantry {
            let key = IngredientNameNormalizer.comparisonKey(item.name)
            remainingByKey[baseKey(key, counted: item.isCounted), default: 0] += item.baseAmount
        }
        var result: [ShoppingListEntry] = []
        for entry in entries {
            let measure = measure(entry)
            let key = baseKey(IngredientNameNormalizer.comparisonKey(entry.name), counted: measure.counted)
            let available = remainingByKey[key] ?? 0
            guard available > 0 else { result.append(entry); continue }
            let missing = measure.base - available
            remainingByKey[key] = max(0, available - measure.base)
            if missing <= 0.5 { continue }
            var reduced = entry
            switch canonicalUnit(entry.unit) {
            case "g":
                reduced.weight = missing.rounded()
            case "kg":
                reduced.weight = (missing / 1_000 * 1_000).rounded() / 1_000
            case _ where measure.counted && isPieceUnit(entry.unit):
                reduced.weight = missing.rounded(.up)
                reduced.num = 0
                reduced.denom = 0
            default:
                break
            }
            result.append(reduced)
        }
        return result
    }

    /// What a bake of the recipe at `scale` takes out of the pantry: for
    /// every need, from the matching items soonest-expiring first, as far
    /// as they reach. Items without any of the need are not listed.
    public static func deductions(for recipe: RecipeExportData, scale: Double, pantry: [StoredPantryItem]) -> [PantryDeduction] {
        let entries = ShoppingListBuilder.entriesToBuy(ShoppingListBuilder.entries(of: recipe), scale: scale)
        var taken: [String: Double] = [:]
        var order: [String] = []
        for need in needs(of: entries, pantry: pantry) {
            var left = need.requiredBase
            let key = IngredientNameNormalizer.comparisonKey(need.name)
            let sources = pantry
                .filter { IngredientNameNormalizer.comparisonKey($0.name) == key && $0.isCounted == need.isCounted && $0.amount > 0 }
                .sorted { ($0.bestBefore ?? .distantFuture) < ($1.bestBefore ?? .distantFuture) }
            for item in sources where left > 0 {
                let take = min(item.baseAmount, left)
                left -= take
                if taken[item.id] == nil { order.append(item.id) }
                taken[item.id, default: 0] += take / (item.unit.grams ?? 1)
            }
        }
        return order.compactMap { id in
            guard let item = pantry.first(where: { $0.id == id }), let amount = taken[id], amount > 0 else { return nil }
            return PantryDeduction(item: item, taken: amount)
        }
    }

    /// How a counted item weighs in the use-up ranking against grams.
    static let gramsPerPieceForRanking = 60.0

    /// What of the items that run out soon the recipe at `scale` would use,
    /// most first. Empty when the recipe touches none of them.
    public static func useUp(_ recipe: RecipeExportData, scale: Double, pantry: [StoredPantryItem],
                             now: Date = Date(), calendar: Calendar = .current) -> [PantryUse] {
        let soon = Pantry.needingAttention(pantry, now: now, calendar: calendar)
        guard !soon.isEmpty else { return [] }
        let entries = ShoppingListBuilder.entriesToBuy(ShoppingListBuilder.entries(of: recipe), scale: scale)
        var uses: [PantryUse] = []
        for need in needs(of: entries, pantry: pantry) {
            let key = IngredientNameNormalizer.comparisonKey(need.name)
            var left = need.requiredBase
            for item in soon where IngredientNameNormalizer.comparisonKey(item.name) == key && item.isCounted == need.isCounted {
                let used = min(item.baseAmount, left)
                guard used > 0 else { continue }
                left -= used
                uses.append(PantryUse(item: item, usedBase: used))
            }
        }
        return uses.sorted { rankingWeight($0) > rankingWeight($1) }
    }

    /// The recipe's standing in the "Vorrat aufbrauchen" list: the grams of
    /// soon-expiring goods it uses, pieces counted as sixty grams each.
    public static func useUpScore(_ uses: [PantryUse]) -> Double {
        uses.reduce(0) { $0 + rankingWeight($1) }
    }

    private static func rankingWeight(_ use: PantryUse) -> Double {
        use.item.isCounted ? use.usedBase * gramsPerPieceForRanking : use.usedBase
    }

    /// "200 g", "1,2 kg", "3 Stück" — the amount of a need as it is read.
    public static func baseText(_ base: Double, counted: Bool, locale: Locale) -> String {
        if counted {
            let pieces = Int(base.rounded(.up))
            return "\(pieces) " + String(localized: "Stück", bundle: AppSettings.localizationBundle, locale: locale)
        }
        if base >= 1_000 {
            let kilos = (base / 1_000).formatted(.number.precision(.fractionLength(0...2)).locale(locale))
            return "\(kilos) kg"
        }
        // Small amounts keep a decimal ("8,5 g"), larger ones are whole grams.
        if base < 10 {
            return "\(base.formatted(.number.precision(.fractionLength(0...1)).locale(locale))) g"
        }
        return "\(Int(base.rounded())) g"
    }

    // MARK: Helpers

    static func needs(of entries: [ShoppingListEntry], pantry: [StoredPantryItem]) -> [PantryNeed] {
        var byKey: [String: (name: String, base: Double, counted: Bool)] = [:]
        var order: [String] = []
        for entry in entries {
            let measure = measure(entry)
            let key = baseKey(IngredientNameNormalizer.comparisonKey(entry.name), counted: measure.counted)
            if byKey[key] == nil {
                order.append(key)
                byKey[key] = (IngredientNameNormalizer.displayName(entry.name), 0, measure.counted)
            }
            byKey[key]?.base += measure.base
        }
        return order.compactMap { key in
            guard let need = byKey[key] else { return nil }
            let nameKey = IngredientNameNormalizer.comparisonKey(need.name)
            let available = pantry
                .filter { IngredientNameNormalizer.comparisonKey($0.name) == nameKey && $0.isCounted == need.counted }
                .reduce(0) { $0 + $1.baseAmount }
            return PantryNeed(name: need.name, requiredBase: need.base, availableBase: available, isCounted: need.counted)
        }
    }

    /// An entry's amount in the base the pantry compares with.
    static func measure(_ entry: ShoppingListEntry) -> (base: Double, counted: Bool) {
        let amount = ShoppingListAmount.forShoppingList(name: entry.name, unit: entry.unit, weight: entry.weight,
                                                        num: entry.num, denom: entry.denom)
        if amount.unit == ShoppingListAmount.pieceUnit {
            return (amount.weight, true)
        }
        return (ShoppingListBuilder.normalizedWeight(of: entry), false)
    }

    private static func baseKey(_ key: String, counted: Bool) -> String {
        counted ? "St|" + key : "g|" + key
    }

    private static func canonicalUnit(_ unit: String) -> String {
        (UnitLocalizer.canonicalAbbreviation(for: unit) ?? unit).lowercased()
    }

    private static func isPieceUnit(_ unit: String) -> Bool {
        ["st", "stk", "stück", "stuck", "pc", "pcs", "piece", "pieces"].contains(canonicalUnit(unit))
    }
}
