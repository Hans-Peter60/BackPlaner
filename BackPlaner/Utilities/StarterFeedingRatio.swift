//
//  StarterFeedingRatio.swift
//  BackPlaner
//
//  The feeding ratio (Anstellgut : Mehl : Wasser) of a recipe that is
//  itself a starter being refreshed on a schedule — read straight off its
//  ingredients, the same way DoughComposition already classifies flour,
//  water and starter by name. Never entered by hand: the ratio is the
//  recipe, so typing it again on every feeding would only drift out of
//  sync with it.
//

import Foundation

enum StarterFeedingRatio {

    struct Ratio: Equatable {
        let starter: Int
        let flour: Int
        let water: Int
    }

    /// `nil` when the recipe does not clearly state all three parts — a
    /// feeding ratio needs starter, flour and water to mean anything.
    static func ratio(for recipe: Recipe) -> Ratio? {
        ratio(components: DoughComposition.components(of: recipe))
    }

    static func ratio(components: [DoughComposition.Component]) -> Ratio? {
        var starterGrams = 0.0
        var flourGrams = 0.0
        var waterGrams = 0.0

        for component in components {
            for ingredient in component.ingredients {
                guard ingredient.grams > 0 else { continue }

                switch DoughComposition.classify(ingredient.name) {
                case .starter: starterGrams += ingredient.grams
                case .flour:   flourGrams += ingredient.grams
                case .water:   waterGrams += ingredient.grams
                case .other:   break
                }
            }
        }

        guard starterGrams > 0, flourGrams > 0, waterGrams > 0 else { return nil }

        let wholeGrams = [starterGrams, flourGrams, waterGrams].map { Int($0.rounded()) }
        let divisor = wholeGrams.reduce(0, Rational.greatestCommonDivisor)
        guard divisor > 0 else { return nil }

        return Ratio(starter: wholeGrams[0] / divisor,
                     flour: wholeGrams[1] / divisor,
                     water: wholeGrams[2] / divisor)
    }
}
