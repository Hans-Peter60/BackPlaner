//
//  Pantry.swift
//  BakePlannerCore
//
//  What the pantry screen works out from its items: how long a packet
//  still keeps, and which names to offer when something new is put in.
//

import Foundation

/// How a best-before date stands against today.
public enum PantryShelfLife: Equatable, Sendable {
    /// No date noted.
    case unknown
    /// Keeps for longer than the warning period.
    case fresh
    /// Runs out within the warning period; the days left (0 = today).
    case soon(days: Int)
    /// The date has passed; the days since.
    case expired(days: Int)

    /// Within how many days a date counts as "soon".
    public static let warningDays = 14

    public static func of(_ bestBefore: Date?, now: Date = Date(), warningDays: Int = warningDays,
                          calendar: Calendar = .current) -> PantryShelfLife {
        guard let bestBefore else { return .unknown }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: bestBefore)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        if days < 0 { return .expired(days: -days) }
        if days <= warningDays { return .soon(days: days) }
        return .fresh
    }

    /// Whether the item wants attention: soon or already over.
    public var needsAttention: Bool {
        switch self {
        case .soon, .expired: return true
        case .unknown, .fresh: return false
        }
    }
}

public enum Pantry {

    /// The ingredient names of the recipes that belong in a pantry — what
    /// one buys, so no water, salt or starter — most used first, each once.
    /// Offered when a new item is typed, so pantry names match the recipes.
    public static func suggestedNames(from recipes: [RecipeExportData]) -> [String] {
        var counts: [String: (name: String, count: Int)] = [:]
        for recipe in recipes {
            for ingredient in recipe.components.flatMap(\.ingredients) {
                guard ShoppingListAmount.belongsOnList(name: ingredient.name) else { continue }
                let key = IngredientNameNormalizer.comparisonKey(ingredient.name)
                let display = IngredientNameNormalizer.displayName(ingredient.name)
                counts[key, default: (display, 0)].count += 1
            }
        }
        return counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(\.name)
    }

    /// The suggestions that fit what was typed so far, the typed text
    /// itself excluded; everything when nothing was typed.
    public static func matchingNames(_ typed: String, in suggestions: [String]) -> [String] {
        let key = IngredientNameNormalizer.comparisonKey(typed)
        guard !key.isEmpty else { return suggestions }
        return suggestions.filter {
            let candidate = IngredientNameNormalizer.comparisonKey($0)
            return candidate != key && candidate.contains(key)
        }
    }

    /// What a bought shopping-list line puts into the pantry: kilograms and
    /// pieces as written, anything else by its weight in grams (the list's
    /// base amount), a fraction of pieces rounded up to whole ones.
    public static func intake(unit: String?, weight: Double, normWeight: Double, num: Int, denom: Int) -> (amount: Double, unit: PantryUnit) {
        let canonical = UnitLocalizer.canonicalAbbreviation(for: unit ?? "") ?? (unit ?? "")
        switch canonical.lowercased() {
        case "kg":
            return (weight, .kilogram)
        case "st", "stk", "stück", "stuck", "pc", "pcs", "piece", "pieces":
            let fraction = denom != 0 ? Double(num) / Double(denom) : 0
            return (max(1, (weight + fraction).rounded(.up)), .piece)
        case "g":
            return (weight, .gram)
        default:
            return (normWeight > 0 ? normWeight : weight, .gram)
        }
    }

    /// The items that run out soon or already have, soonest first.
    public static func needingAttention(_ items: [StoredPantryItem], now: Date = Date(),
                                        calendar: Calendar = .current) -> [StoredPantryItem] {
        items
            .filter { PantryShelfLife.of($0.bestBefore, now: now, calendar: calendar).needsAttention }
            .sorted { ($0.bestBefore ?? .distantPast) < ($1.bestBefore ?? .distantPast) }
    }
}
