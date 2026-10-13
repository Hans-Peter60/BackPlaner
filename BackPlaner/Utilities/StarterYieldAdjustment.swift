//
//  StarterYieldAdjustment.swift
//  BackPlaner
//
//  Using a starter of a different dough yield (TA) than the recipe asks
//  for. A recipe wants 100 g of Anstellgut at TA 150; the jar holds TA 210.
//  The flour the starter brings must stay the same, so more of the softer
//  starter goes in — and the water it brings with it comes off the dough's
//  own water, so the dough as a whole ends up where the recipe meant it.
//  The counterpart of FlourSubstitution, for the sourdough instead of the
//  flour.
//

import Foundation
import SwiftUI

enum StarterYieldAdjustment {

    // MARK: - The starter line of a recipe

    /// A starter the recipe calls for, at the TA it is taken apart with.
    struct Source: Equatable {
        let kind: DoughComposition.StarterKind
        /// Grams as the recipe states them.
        let grams: Double
        let doughYield: Double
        /// Whether the TA stood in the recipe or came from the settings.
        let yieldSource: DoughComposition.YieldSource

        var flour: Double { grams * 100 / doughYield }
        var water: Double { grams - flour }
    }

    /// The starter an ingredient line names, or nil for anything else: a
    /// flour, water, a line without weight — or a line that stands for a
    /// component of this very recipe ("200 g Sauerteig" with a component
    /// called Sauerteig), whose dough yield is that component's business.
    static func recognize(name: String,
                          grams: Double,
                          weight: Double,
                          numerator: Int,
                          denominator: Int,
                          componentNames: [String],
                          yields: DoughComposition.StarterYields = .stored) -> Source? {
        guard grams > 0 else { return nil }
        guard case .starter(let kind) = DoughComposition.classify(name) else { return nil }
        // Only the starters one keeps: a poolish or biga is TA 200 or 150 by
        // definition, there is nothing on hand to swap it for.
        guard kind == .sourdough || kind == .lievitoMadre else { return nil }
        guard ComponentProductMatcher.referencedComponent(name: name,
                                                          weight: weight,
                                                          numerator: numerator,
                                                          denominator: denominator,
                                                          componentNames: componentNames) == nil
        else { return nil }

        let (yield, source) = DoughComposition.doughYield(of: kind, in: name, yields: yields)
        return Source(kind: kind, grams: grams, doughYield: yield, yieldSource: source)
    }

    static func recognize(_ ingredient: RecipeExportIngredient,
                          componentNames: [String],
                          yields: DoughComposition.StarterYields = .stored) -> Source? {
        recognize(name: ingredient.name,
                  grams: ingredient.normWeight > 0 ? ingredient.normWeight : ingredient.weight,
                  weight: ingredient.weight,
                  numerator: ingredient.num,
                  denominator: ingredient.denom,
                  componentNames: componentNames,
                  yields: yields)
    }

    static func recognize(_ ingredient: TotalIngredientData,
                          componentNames: [String],
                          yields: DoughComposition.StarterYields = .stored) -> Source? {
        recognize(name: ingredient.name,
                  grams: ingredient.weight,
                  weight: ingredient.weight,
                  numerator: ingredient.numerator,
                  denominator: ingredient.denominator,
                  componentNames: componentNames,
                  yields: yields)
    }

    // MARK: - The arithmetic

    /// Grams of starter at `targetYield` that carry the same flour as
    /// `grams` of starter at `sourceYield`.
    static func starterGrams(grams: Double, from sourceYield: Double, to targetYield: Double) -> Double {
        guard sourceYield > 0 else { return grams }
        return grams * targetYield / sourceYield
    }

    /// Grams of water to add to the dough (negative: to take away) once the
    /// starter is exchanged, so flour and water of the whole dough stay as
    /// the recipe meant them. Exactly the water the new starter brings more
    /// or less, which is the difference in starter weight.
    static func waterDelta(grams: Double, from sourceYield: Double, to targetYield: Double) -> Double {
        grams - starterGrams(grams: grams, from: sourceYield, to: targetYield)
    }

    // MARK: - Naming

    private static let yieldExpression = try? NSRegularExpression(pattern: #"\bTA\s*:?\s*(\d{3})\b"#, options: [.caseInsensitive])
    private static let hydrationExpression = try? NSRegularExpression(pattern: #"(\d{2,3})(\s*%\s*hydr)"#, options: [.caseInsensitive])

    /// The ingredient line with the new TA written into it: an existing
    /// "TA 150" or "50 % Hydration" is replaced, otherwise "(TA 210)" is
    /// appended — so the dough yield reads the right figure from the copy.
    static func renamed(_ name: String, toYield yield: Double) -> String {
        let whole = Int(yield.rounded())
        let range = NSRange(name.startIndex..., in: name)

        if let match = yieldExpression?.firstMatch(in: name, range: range),
           let matchRange = Range(match.range, in: name) {
            return name.replacingCharacters(in: matchRange, with: "TA \(whole)")
        }
        if let match = hydrationExpression?.firstMatch(in: name, range: range),
           let numberRange = Range(match.range(at: 1), in: name) {
            return name.replacingCharacters(in: numberRange, with: String(whole - 100))
        }
        return "\(name) (TA \(whole))"
    }

    // MARK: - Hints

    enum Hint: Hashable, Identifiable {
        case softer
        case firmer
        case bigStep
        case assumedYield

        var id: Self { self }

        var text: LocalizedStringKey {
            switch self {
            case .softer:
                return "Weicheres Anstellgut (höhere TA) gärt schneller und säuert milder – die Reifezeit des Sauerteigs eher etwas kürzer ansetzen."
            case .firmer:
                return "Festeres Anstellgut (niedrigere TA) arbeitet langsamer und säuert kräftiger – etwas mehr Reifezeit einplanen."
            case .bigStep:
                return "Bei großen TA-Unterschieden lohnt es sich, das Anstellgut vorher mit ein bis zwei Fütterungen auf die gewünschte TA umzustellen."
            case .assumedYield:
                return "Das Rezept nennt keine TA für sein Anstellgut; angenommen ist die TA aus den Einstellungen. Steht sie im Rezept, trage sie in den Zutatennamen ein, etwa „Anstellgut TA 150“."
            }
        }
    }

    static func hints(from sourceYield: Double, to targetYield: Double, yieldSource: DoughComposition.YieldSource) -> [Hint] {
        var hints: [Hint] = []
        if yieldSource == .setting { hints.append(.assumedYield) }
        if targetYield > sourceYield { hints.append(.softer) }
        if targetYield < sourceYield { hints.append(.firmer) }
        if abs(targetYield - sourceYield) >= 40 { hints.append(.bigStep) }
        return hints
    }

    // MARK: - Applying to a recipe

    struct Applied: Equatable {
        var recipe: RecipeExportData
        let source: Source
        let targetYield: Double
        /// Whole grams of starter after the exchange.
        let starterGrams: Double
        /// Whole grams the dough's water has to move by (negative: less).
        let waterDelta: Double
        /// False when the component has no poured liquid to take it from.
        let waterAdjusted: Bool
        /// The line that was moved: "Wasser", or the milk or beer standing
        /// in for it in a component without water.
        let adjustedLiquidName: String?
        /// Grams that could not be taken away because the liquid line had
        /// less than that; zero when everything fitted.
        let waterShortfall: Double
    }

    /// The recipe with one starter line rescaled to `targetYield` and the
    /// liquid of the same component moved by what the new starter brings
    /// more or less. Flour and water of the dough stay the same; the copy
    /// gets the TA added to its name.
    static func apply(to recipe: RecipeExportData,
                      componentIndex: Int,
                      ingredientIndex: Int,
                      targetYield: Double,
                      yields: DoughComposition.StarterYields = .stored) -> Applied? {
        guard recipe.components.indices.contains(componentIndex),
              recipe.components[componentIndex].ingredients.indices.contains(ingredientIndex),
              targetYield > 100
        else { return nil }

        var copy = recipe
        var ingredient = copy.components[componentIndex].ingredients[ingredientIndex]
        guard let source = recognize(ingredient, componentNames: recipe.components.map(\.name), yields: yields) else { return nil }

        let factor = targetYield / source.doughYield
        let starterAfter = (source.grams * factor).rounded()
        let delta = (source.grams - starterAfter).rounded()

        ingredient.name = renamed(ingredient.name, toYield: targetYield)
        ingredient.weight = (ingredient.weight * factor).rounded()
        if ingredient.normWeight > 0 {
            ingredient.normWeight = starterAfter
        }
        copy.components[componentIndex].ingredients[ingredientIndex] = ingredient
        copy.totalWeight += starterAfter - source.grams

        var waterAdjusted = false
        var adjustedLiquidName: String?
        var shortfall = 0.0
        let lines = copy.components[componentIndex].ingredients
        if delta != 0,
           let liquidIndex = lines.firstIndex(where: FlourSubstitution.isPlainWater)
            ?? lines.firstIndex(where: FlourSubstitution.isPouredLiquid) {
            var liquid = lines[liquidIndex]
            // Never below zero: what does not fit is reported instead.
            let moved = max(delta, -liquid.weight)
            shortfall = delta - moved
            liquid.weight += moved
            if liquid.normWeight > 0 {
                liquid.normWeight = max(0, liquid.normWeight + moved)
            }
            copy.components[componentIndex].ingredients[liquidIndex] = liquid
            copy.totalWeight += moved
            waterAdjusted = true
            adjustedLiquidName = IngredientNameNormalizer.displayName(liquid.name)
        }

        copy.name = "\(recipe.name) – TA \(Int(targetYield.rounded()))"
        return Applied(recipe: copy,
                       source: source,
                       targetYield: targetYield,
                       starterGrams: starterAfter,
                       waterDelta: delta,
                       waterAdjusted: waterAdjusted,
                       adjustedLiquidName: adjustedLiquidName,
                       waterShortfall: abs(shortfall))
    }
}
