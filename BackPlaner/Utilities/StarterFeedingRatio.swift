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

/// Whether a recipe is a starter being fed rather than something baked.
/// The "+ Fütterung" tab, "Nächste Fütterung" and Siri's list of starters
/// hang on this. It used to be "has a rhythm", which made every bread
/// planned on a rhythm a starter and expected a feeding of it.
///
/// Decided from what the recipe is, in any of its languages, not from a
/// flag nobody maintains: its ingredients give a feeding ratio (starter,
/// flour and water, see `StarterFeedingRatio`), and nothing in its steps
/// uses an oven — no bake, no preheating, no oven temperature.
///
/// A recipe made of nothing but starter, flour and water is a feeding even
/// when a step mentions the oven: "im ausgeschalteten Backofen mit Licht
/// reifen lassen" uses it as a proofing box, "bis zum nächsten Backen kühl
/// lagern" names the bake it is kept for. Only oven heat — a stated oven
/// temperature or a preheating step — says that something is baked. A
/// bread has salt and more besides. A tag such as "Anstellgut" settles it
/// by hand in the remaining cases ("Backofen auf 50 °C vorheizen,
/// ausschalten, hineinstellen"). "Sauerteig" is no such tag: bakers put
/// it on their bread.
enum StarterRecipe {

    /// Tags that mark a recipe as a starter, folded (no case, no accents),
    /// so "Fütterung" and "futterung" both count.
    static let overrideTags: Set<String> = ["anstellgut", "asg", "futterung", "auffrischen", "starter",
                                            "feeding", "refresh", "levain chef", "rafraichi"]

    static func isStarterFeeding(instructions: [String],
                                 components: [DoughComposition.Component],
                                 tags: [String]) -> Bool {
        guard StarterFeedingRatio.ratio(components: components) != nil else { return false }
        if tags.contains(where: { overrideTags.contains(fold($0)) }) { return true }
        if !BakePlanValidator.usesOven(instructions) { return true }
        return consistsOfFeedingParts(components) && !instructions.contains(where: heatsTheOven)
    }

    /// Whether every weighed ingredient is starter, flour or water.
    static func consistsOfFeedingParts(_ components: [DoughComposition.Component]) -> Bool {
        components.flatMap(\.ingredients).filter { $0.grams > 0 }.allSatisfy {
            DoughComposition.classify($0.name) != .other
        }
    }

    /// Whether a step heats the oven: it states an oven temperature or
    /// preheats. Mentioning the oven or the word "backen" is not enough.
    private static func heatsTheOven(_ instruction: String) -> Bool {
        BakePlanValidator.isPreheatInstruction(instruction) || BakePlan.ovenTemperature(in: instruction) != nil
    }

    static func isStarterFeeding(_ recipe: Recipe) -> Bool {
        isStarterFeeding(instructions: recipe.instructionsArray.map(\.instruction),
                         components: DoughComposition.components(of: recipe),
                         tags: recipe.tags)
    }

    static func isStarterFeeding(_ recipe: RecipeFB) -> Bool {
        isStarterFeeding(instructions: recipe.instructions.map(\.instruction),
                         components: DoughComposition.components(of: recipe),
                         tags: recipe.tags)
    }

    private static func fold(_ tag: String) -> String {
        tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
