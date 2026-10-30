//
//  ComponentColumn.swift
//  BackPlaner
//
//  A recipe's components with their ingredients, whichever model the recipe
//  comes from, and the summed ingredients worked out from them. Used by the
//  recipe screens, the PDF export and the reminders.
//

import BakePlannerCore
import Foundation

struct TotalIngredientData {
    let name: String
    let unit: String
    let weight: Double
    let numerator: Int
    let denominator: Int
}

/// One component of a recipe: its name and the ingredients listed under it.
///
/// Exists so the same card can serve both recipe models — the Firebase
/// `ComponentFB` of the public database and the Core Data `Component` of the
/// user's own recipes — without the view knowing either.
struct ComponentColumn: Identifiable {
    let id: String
    let name: String
    let ingredients: [TotalIngredientData]

    /// The components of a recipe from the public database.
    static func columns(of components: [ComponentFB]) -> [ComponentColumn] {
        components
            .sorted { $0.number < $1.number }
            .enumerated()
            .map { index, component in
                ComponentColumn(
                    id: component.id ?? "component-\(index)",
                    name: component.name,
                    ingredients: component.ingredients
                        .sorted { $0.number < $1.number }
                        .map {
                            TotalIngredientData(name: $0.name,
                                                unit: $0.unit,
                                                weight: $0.weight,
                                                numerator: $0.num,
                                                denominator: $0.denom)
                        }
                )
            }
    }

    /// The components of a recipe snapshot. Screens that offer the flour
    /// substitution build their columns from the same snapshot the sheet
    /// gets, so a tapped line's index is guaranteed to mean the same
    /// ingredient in both — sorting the Core Data set twice did not, once
    /// several ingredients shared a `number`.
    static func columns(of recipe: RecipeExportData) -> [ComponentColumn] {
        recipe.components.enumerated().map { index, component in
            ComponentColumn(
                id: "\(index)-\(component.name)",
                name: component.name,
                ingredients: component.ingredients.map {
                    TotalIngredientData(name: $0.name,
                                        unit: $0.unit ?? "",
                                        weight: $0.weight,
                                        numerator: $0.num,
                                        denominator: $0.denom)
                }
            )
        }
    }
}

/// The summed ingredients of a recipe — the list the "Gesamtzutaten" card
/// shows.
enum TotalIngredientsList {

    /// The summed ingredients without water and salt — in whichever language
    /// the recipe is shown — and without components used as ingredients; the
    /// same list the card shows, for other consumers such as the PDF export.
    static func totalIngredients(of components: [ComponentColumn]) -> [TotalIngredient] {
        let componentNames = components.map(\.name)
        let rawIngredients = components.enumerated().flatMap { index, component in
            component.ingredients.filter { ingredient in
                guard !ShoppingListAmount.isWater(ingredient.name),
                      !ShoppingListAmount.isSalt(ingredient.name) else { return false }
                // A row that names its own component is that component's
                // raw ingredient, not a reference: "104 g Kartoffeln" under
                // "Kartoffeln (gekocht)" is what one buys, while the same
                // line in the main dough takes the cooked potatoes over
                // from that component. Dropping both left the potatoes out
                // of the list.
                return !ShoppingListAmount.standsForAnotherComponent(
                    name: ingredient.name,
                    weight: ingredient.weight,
                    num: ingredient.numerator,
                    denom: ingredient.denominator,
                    componentIndex: index,
                    componentNames: componentNames
                )
            }
        }
        return TotalIngredient.aggregate(rawIngredients)
    }

    /// The summed ingredients as display lines ("• 268 g Weizenmehl 1050").
    static func aggregatedLines(of components: [ComponentColumn], scale: Double) -> [String] {
        totalIngredients(of: components).map { ingredient in
            "• " + Rational.getPortion(unit: ingredient.unit,
                                       weight: ingredient.weight,
                                       num: ingredient.numerator,
                                       denom: ingredient.denominator,
                                       scale: scale)
                + ingredient.name
        }
    }
}

struct TotalIngredient: Identifiable {
    let id: String
    let name: String
    let unit: String
    let weight: Double
    let numerator: Int
    let denominator: Int

    static func aggregate(_ ingredients: [TotalIngredientData]) -> [TotalIngredient] {
        var grouped: [String: Accumulator] = [:]

        for ingredient in ingredients {
            let normalizedName = IngredientNameNormalizer.displayName(ingredient.name)
            let normalizedUnit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedName.localizedLowercase + "|" + normalizedUnit.localizedLowercase

            var accumulator = grouped[key] ?? Accumulator(
                name: normalizedName,
                unit: normalizedUnit
            )
            accumulator.add(
                weight: ingredient.weight,
                numerator: ingredient.numerator,
                denominator: ingredient.denominator
            )
            grouped[key] = accumulator
        }

        return grouped.map { key, accumulator in
            accumulator.ingredient(id: key)
        }
        .sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

private struct Accumulator {
    let name: String
    let unit: String
    private var decimalAmount = 0.0
    private var fractionNumerator = 0
    private var fractionDenominator = 1

    mutating func add(weight: Double, numerator: Int, denominator: Int) {
        if weight != 0 {
            decimalAmount += weight
        } else if numerator != 0, denominator != 0 {
            fractionNumerator = fractionNumerator * denominator + numerator * fractionDenominator
            fractionDenominator *= denominator

            let divisor = greatestCommonDivisor(abs(fractionNumerator), abs(fractionDenominator))
            fractionNumerator /= divisor
            fractionDenominator /= divisor
        }
    }

    func ingredient(id: String) -> TotalIngredient {
        if decimalAmount != 0 {
            let combinedAmount = decimalAmount + Double(fractionNumerator) / Double(fractionDenominator)
            return TotalIngredient(
                id: id,
                name: name,
                unit: unit,
                weight: combinedAmount,
                numerator: 0,
                denominator: 0
            )
        }

        return TotalIngredient(
            id: id,
            name: name,
            unit: unit,
            weight: 0,
            numerator: fractionNumerator,
            denominator: fractionDenominator
        )
    }

    private func greatestCommonDivisor(_ first: Int, _ second: Int) -> Int {
        var a = first
        var b = second

        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }

        return max(a, 1)
    }
}
