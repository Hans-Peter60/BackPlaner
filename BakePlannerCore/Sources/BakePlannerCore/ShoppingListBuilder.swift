//
//  ShoppingListBuilder.swift
//  BakePlannerCore
//
//  Putting a recipe's ingredients on a shopping list: what is bought at
//  all, at which amount, and how it joins what the list already holds.
//  The rules the iOS app applied in ShoppingCartSelectFormView, moved here
//  unchanged so Android follows them too.
//

import Foundation

/// One ingredient on its way to a shopping list, independent of where it
/// came from.
public struct ShoppingListEntry: Equatable {
    public var name: String
    public var unit: String
    public var weight: Double
    public var num: Int
    public var denom: Int

    public init(name: String, unit: String, weight: Double, num: Int, denom: Int) {
        self.name = name
        self.unit = unit
        self.weight = weight
        self.num = num
        self.denom = denom
    }

    /// The entry at the serving scale chosen in the recipe; 1.0 is the recipe
    /// as stored. Done before anything else happens to the entry, so eggs by
    /// weight are doubled first and only then turned into pieces.
    public func scaled(by scale: Double) -> ShoppingListEntry {
        let amount = ShoppingListAmount.scaled(weight: weight, num: num, denom: denom, by: scale)
        return ShoppingListEntry(name: name, unit: unit, weight: amount.weight, num: amount.num, denom: amount.denom)
    }
}

/// One line of a shopping list. `key` is the store's own key for a line
/// already kept, nil for a new one.
public struct ShoppingListLine: Equatable {
    public var key: String?
    public var name: String
    public var unit: String?
    public var weight: Double
    public var normWeight: Double
    public var num: Int
    public var denom: Int

    public init(key: String? = nil, name: String, unit: String?, weight: Double, normWeight: Double,
                num: Int, denom: Int) {
        self.key = key
        self.name = name
        self.unit = unit
        self.weight = weight
        self.normWeight = normWeight
        self.num = num
        self.denom = denom
    }
}

public enum ShoppingListBuilder {

    /// The ingredients of a recipe, without the rows that stand for another
    /// of its components.
    public static func entries(of recipe: RecipeExportData) -> [ShoppingListEntry] {
        let componentNames = recipe.components.map(\.name)
        return recipe.components.enumerated().flatMap { index, component in
            component.ingredients.filter { ingredient in
                !ShoppingListAmount.standsForAnotherComponent(name: ingredient.name, weight: ingredient.weight,
                                                              num: ingredient.num, denom: ingredient.denom,
                                                              componentIndex: index, componentNames: componentNames)
            }
        }.map { ingredient in
            ShoppingListEntry(name: ingredient.name, unit: ingredient.unit ?? "", weight: ingredient.weight,
                              num: ingredient.num, denom: ingredient.denom)
        }
    }

    /// The entries at `scale` that are bought at all. Water, salt and
    /// starters stay off the list, whatever language the recipe names them
    /// in; so does anything without an amount or a unit.
    public static func entriesToBuy(_ entries: [ShoppingListEntry], scale: Double) -> [ShoppingListEntry] {
        entries
            .map { $0.scaled(by: scale) }
            .filter { entry in
                let hasUnit = !entry.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return ShoppingListAmount.belongsOnList(name: entry.name) && normalizedWeight(of: entry) > 0 && hasUnit
            }
    }

    /// `lines` with `entries` added: eggs and the like converted to pieces,
    /// the lines already there brought under one name each, and every entry
    /// joined with the line of the same ingredient — in another unit of the
    /// same kind converted — or put on a line of its own.
    ///
    /// The lines are taken in the order of their names, as the iOS app has
    /// always kept them, so where two lines could take an entry it is the
    /// same one on every device. New lines come at the end.
    public static func adding(_ entries: [ShoppingListEntry], to lines: [ShoppingListLine]) -> [ShoppingListLine] {
        // Converted for shopping before anything is merged, so eggs from one
        // recipe and eggs from another meet as pieces.
        let listEntries = entries.map(forShopping)
        let byName = lines.enumerated().sorted { first, second in
            first.element.name != second.element.name
                ? first.element.name < second.element.name
                : first.offset < second.offset
        }.map(\.element)
        var result = harmonized(byName)
        for entry in listEntries {
            merge(entry, into: &result)
        }
        return result
    }

    // MARK: Steps

    /// Converts a recipe amount into the amount to buy — eggs by the piece
    /// instead of by weight, see ``ShoppingListAmount``.
    static func forShopping(_ entry: ShoppingListEntry) -> ShoppingListEntry {
        let amount = ShoppingListAmount.forShoppingList(name: entry.name, unit: entry.unit, weight: entry.weight,
                                                        num: entry.num, denom: entry.denom)
        return ShoppingListEntry(name: entry.name, unit: amount.unit, weight: amount.weight,
                                 num: amount.num, denom: amount.denom)
    }

    static func harmonized(_ lines: [ShoppingListLine]) -> [ShoppingListLine] {
        var result: [ShoppingListLine] = []
        var canonical: [String: Int] = [:]

        for var line in lines {
            let normalizedName = IngredientNameNormalizer.displayName(line.name)
            let normalizedUnit = (line.unit ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedLowercase
            let key = IngredientNameNormalizer.comparisonKey(normalizedName) + "|" + normalizedUnit

            line.name = normalizedName

            if let index = canonical[key] {
                result[index].weight += line.weight
                result[index].normWeight += line.normWeight
                addFractions(num: line.num, denom: line.denom, to: &result[index])
            } else {
                canonical[key] = result.count
                result.append(line)
            }
        }
        return result
    }

    /// The amount in its base unit. Computed rather than read from the
    /// recipe: a stored value can predate an edit, and a cloud recipe may
    /// carry none.
    static func normalizedWeight(of entry: ShoppingListEntry) -> Double {
        CalcIngredientWeight().calcIngredientWeight(weight: entry.weight, unit: entry.unit, name: entry.name,
                                                    num: entry.num, denom: entry.denom)
    }

    static func merge(_ entry: ShoppingListEntry, into lines: inout [ShoppingListLine]) {
        let ingredientName = IngredientNameNormalizer.displayName(entry.name)
        let comparisonKey = IngredientNameNormalizer.comparisonKey(entry.name)

        guard let index = lines.firstIndex(where: {
            IngredientNameNormalizer.comparisonKey($0.name) == comparisonKey
        }) else {
            lines.append(ShoppingListLine(name: ingredientName, unit: entry.unit, weight: entry.weight,
                                          normWeight: normalizedWeight(of: entry), num: entry.num,
                                          denom: entry.denom))
            return
        }

        lines[index].name = ingredientName

        if (lines[index].unit ?? "") == entry.unit {
            lines[index].weight += entry.weight
            lines[index].normWeight += normalizedWeight(of: entry)
            addFractions(num: entry.num, denom: entry.denom, to: &lines[index])
        } else {
            mergeWithUnitConversion(entry, into: &lines[index])
        }
    }

    static func addFractions(num: Int, denom: Int, to existing: inout ShoppingListLine) {
        guard existing.denom != 0, denom != 0 else { return }
        guard existing.num != 0 || num != 0 else { return }

        let combinedNum = (existing.num * denom) + (num * existing.denom)
        let combinedDenom = existing.denom * denom
        let gcd = Rational.greatestCommonDivisor(combinedNum, combinedDenom)

        guard gcd != 0 else { return }
        existing.num = combinedNum / gcd
        existing.denom = combinedDenom / gcd
    }

    /// Converts the entry into the unit already on the list and adds it
    /// there. Returns false when the two units share no base unit; the
    /// amount is then not added, as the iOS app has always done.
    @discardableResult
    static func mergeWithUnitConversion(_ entry: ShoppingListEntry, into existing: inout ShoppingListLine) -> Bool {
        var existingSet = UnitSetFB()
        var entrySet = UnitSetFB()

        guard let storedUnit = existing.unit, !storedUnit.isEmpty else { return false }
        guard !entry.unit.isEmpty else { return false }
        // Imported spellings ("tsp") count as the bundled unit they mean.
        let existingUnit = UnitLocalizer.canonicalAbbreviation(for: storedUnit) ?? storedUnit
        let entryUnit = UnitLocalizer.canonicalAbbreviation(for: entry.unit) ?? entry.unit

        for unitSet in GlobalVariables.unitSets {
            if entryUnit.localizedLowercase.contains(unitSet.name) || entryUnit == unitSet.abbreviation {
                entrySet = unitSet
            }
            if existingUnit.localizedLowercase.contains(unitSet.name) || existingUnit == unitSet.abbreviation {
                existingSet = unitSet
            }
        }

        guard !existingSet.baseUnit.isEmpty, existingSet.baseUnit == entrySet.baseUnit else { return false }
        guard existingSet.factor != 0 else { return false }

        existing.weight += entry.weight / existingSet.factor * entrySet.factor
        existing.normWeight += normalizedWeight(of: entry) / existingSet.factor * entrySet.factor

        if existing.denom != 0, entry.denom != 0, existing.num != 0 || entry.num != 0 {
            let num = Int((Double(existing.num * entry.denom) * existingSet.factor)
                          + (Double(entry.num * existing.denom) * entrySet.factor))
            let denom = existing.denom * entry.denom
            let gcd = Rational.greatestCommonDivisor(num, denom)
            if gcd != 0 {
                existing.num = num / gcd
                existing.denom = denom / gcd
            }
        }
        return true
    }
}
