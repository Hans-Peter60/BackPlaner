//
//  FlourSubstitution.swift
//  BackPlaner
//
//  Swapping one flour for another: which flour a recipe line names, how
//  much more or less water the replacement binds, and what else changes in
//  the handling. Flours are exchanged 1:1 by weight; only the water moves.
//  The water figures are the baker's rules of thumb relative to wheat 550
//  — they vary by mill and harvest, so they are a starting point the dough
//  corrects, like the friction factor of the dough-temperature calculator.
//  Gluten-free flours are deliberately absent: they are not a 1:1 swap.
//

import BakePlannerCore
import Foundation

enum FlourSubstitution {

    // MARK: - Grains and millings

    enum Grain: String, CaseIterable, Identifiable {
        case wheat, spelt, rye, emmer, einkorn, durum

        var id: String { rawValue }

        /// "Weizen" — the heading of a picker section and the first word of
        /// a flour's title.
        var title: String {
            switch self {
            case .wheat:   return String(localized: "Weizen", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Getreide")
            case .spelt:   return String(localized: "Dinkel", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Getreide")
            case .rye:     return String(localized: "Roggen", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Getreide")
            case .emmer:   return String(localized: "Emmer", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Getreide")
            case .einkorn: return String(localized: "Einkorn", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Getreide")
            case .durum:   return String(localized: "Hartweizen", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Getreide")
            }
        }

        /// "Weizenmehl" — the first word of an ingredient line written into a
        /// recipe copy. A real ingredient name, so it must stay recognisable
        /// as flour by `DoughComposition.classify` in every language.
        var flourWord: String {
            switch self {
            case .wheat:   return String(localized: "Weizenmehl", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Zutatenname")
            case .spelt:   return String(localized: "Dinkelmehl", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Zutatenname")
            case .rye:     return String(localized: "Roggenmehl", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Zutatenname")
            case .emmer:   return String(localized: "Emmermehl", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Zutatenname")
            case .einkorn: return String(localized: "Einkornmehl", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Zutatenname")
            case .durum:   return String(localized: "Hartweizenmehl", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Zutatenname")
            }
        }
    }

    /// How far a flour is milled out. German type numbers and French T
    /// numbers are kept apart because bakers read them differently, even
    /// where they describe much the same flour.
    enum Milling: Hashable {
        case type(Int)
        case french(Int)
        case light
        case wholeGrain
        case semolina

        var title: String {
            switch self {
            case .type(let number):   return String(number)
            case .french(let number): return "T\(number)"
            case .light:      return String(localized: "hell", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Mehl: helle Ausmahlung")
            case .wholeGrain: return String(localized: "Vollkorn", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Mehl")
            case .semolina:   return String(localized: "Grieß", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Hartweizengrieß")
            }
        }

        /// A position on one scale, so the nearest catalogue entry can be
        /// found for a type a grain is not sold in ("Dinkelmehl 550").
        var ashKey: Int {
            switch self {
            case .type(let number): return number
            case .french(let number):
                switch number {
                case 45:  return 405
                case 55:  return 550
                case 65:  return 650
                case 80:  return 1050
                case 85:  return 1000
                case 110: return 1300
                case 130: return 1370
                case 150: return 1700
                default:  return 1740
                }
            case .light:      return 500
            case .semolina:   return 700
            case .wholeGrain: return 2000
            }
        }
    }

    struct Flour: Hashable, Identifiable {
        let grain: Grain
        let milling: Milling
        /// Water the flour binds beyond wheat 550, as a share of its weight.
        let extraWater: Double

        var id: String { "\(grain.rawValue)-\(milling)" }
        var isWholeGrain: Bool { milling == .wholeGrain }

        /// The same as the ingredient line, for pickers and the result line:
        /// adjectives agree with "Farine …" in French, where "Blé complète"
        /// (grain + grade) did not.
        var title: String { ingredientName }

        /// The ingredient line a recipe copy gets: "Dinkelmehl 630",
        /// "Roggenmehl Vollkorn", "Hartweizengrieß".
        var ingredientName: String {
            if grain == .durum, milling == .semolina {
                return String(localized: "Hartweizengrieß", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Zutatenname")
            }
            return "\(grain.flourWord) \(milling.title)"
        }
    }

    // MARK: - Catalogue

    static let catalog: [Flour] = [
        Flour(grain: .wheat, milling: .type(405),  extraWater: -0.02),
        Flour(grain: .wheat, milling: .type(550),  extraWater:  0.00),
        Flour(grain: .wheat, milling: .type(812),  extraWater:  0.02),
        Flour(grain: .wheat, milling: .type(1050), extraWater:  0.04),
        Flour(grain: .wheat, milling: .type(1600), extraWater:  0.07),
        Flour(grain: .wheat, milling: .wholeGrain, extraWater:  0.10),
        Flour(grain: .wheat, milling: .french(45),  extraWater: -0.02),
        Flour(grain: .wheat, milling: .french(55),  extraWater:  0.00),
        Flour(grain: .wheat, milling: .french(65),  extraWater:  0.01),
        Flour(grain: .wheat, milling: .french(80),  extraWater:  0.04),
        Flour(grain: .wheat, milling: .french(110), extraWater:  0.07),
        Flour(grain: .wheat, milling: .french(150), extraWater:  0.10),

        Flour(grain: .spelt, milling: .type(630),  extraWater: -0.04),
        Flour(grain: .spelt, milling: .type(812),  extraWater: -0.02),
        Flour(grain: .spelt, milling: .type(1050), extraWater:  0.00),
        Flour(grain: .spelt, milling: .wholeGrain, extraWater:  0.05),

        Flour(grain: .rye, milling: .type(815),  extraWater: 0.08),
        Flour(grain: .rye, milling: .type(997),  extraWater: 0.10),
        Flour(grain: .rye, milling: .type(1150), extraWater: 0.12),
        Flour(grain: .rye, milling: .type(1370), extraWater: 0.15),
        Flour(grain: .rye, milling: .type(1740), extraWater: 0.18),
        Flour(grain: .rye, milling: .wholeGrain, extraWater: 0.20),

        Flour(grain: .emmer, milling: .light,      extraWater: -0.03),
        Flour(grain: .emmer, milling: .wholeGrain, extraWater:  0.04),

        Flour(grain: .einkorn, milling: .light,      extraWater: -0.08),
        Flour(grain: .einkorn, milling: .wholeGrain, extraWater: -0.04),

        Flour(grain: .durum, milling: .semolina,   extraWater: 0.05),
        Flour(grain: .durum, milling: .light,      extraWater: 0.03),
        Flour(grain: .durum, milling: .wholeGrain, extraWater: 0.08)
    ]

    static func flours(of grain: Grain) -> [Flour] {
        catalog.filter { $0.grain == grain }
    }

    /// The reference every water figure is relative to.
    static var wheat550: Flour {
        catalog.first { $0.grain == .wheat && $0.milling == .type(550) }!
    }

    private static func defaultFlour(of grain: Grain) -> Flour {
        switch grain {
        case .wheat:   return wheat550
        case .spelt:   return flours(of: .spelt).first { $0.milling == .type(630) }!
        case .rye:     return flours(of: .rye).first { $0.milling == .type(1150) }!
        case .emmer:   return flours(of: .emmer).first { $0.milling == .light }!
        case .einkorn: return flours(of: .einkorn).first { $0.milling == .light }!
        case .durum:   return flours(of: .durum).first { $0.milling == .semolina }!
        }
    }

    // MARK: - Recognition

    // "Petit épeautre" is einkorn, not spelt, so einkorn is tested first.
    private static let einkornWords = ["einkorn", "petit epeautre", "engrain"]
    private static let emmerWords   = ["emmer", "amidonnier"]
    private static let durumWords   = ["hartweizen", "durum", "semola", "semolina", "semoule"]
    private static let ryeWords     = ["roggen", "rye", "seigle"]
    private static let speltWords   = ["dinkel", "spelt", "epeautre"]
    private static let wholeGrainWords = ["vollkorn", "whole", "complet", "integral", "wholemeal"]
    private static let semolinaWords   = ["gries", "griess", "grieß", "semola", "semolina", "semoule"]
    private static let lightWords      = ["hell", "light", "clair", "blanche", "bianca"]

    private static let typeExpression   = try? NSRegularExpression(pattern: #"(?<!\d)(405|550|630|812|815|997|1050|1150|1370|1600|1740)(?!\d)"#)
    private static let frenchExpression = try? NSRegularExpression(pattern: #"\bt\s?-?(45|55|65|80|85|110|130|150|170)\b"#)

    /// The catalogue flour an ingredient line names, or nil when the line
    /// is not a flour at all. A grain without a type gets that grain's
    /// everyday flour; a type the grain is not sold in gets the nearest one.
    static func recognize(_ name: String) -> Flour? {
        guard DoughComposition.isFlour(name) else { return nil }
        let key = comparisonKey(name)

        let grain: Grain
        if einkornWords.contains(where: key.contains)    { grain = .einkorn }
        else if emmerWords.contains(where: key.contains) { grain = .emmer }
        else if durumWords.contains(where: key.contains) { grain = .durum }
        else if ryeWords.contains(where: key.contains)   { grain = .rye }
        else if speltWords.contains(where: key.contains) { grain = .spelt }
        else                                             { grain = .wheat }

        let candidates = flours(of: grain)

        if wholeGrainWords.contains(where: key.contains) {
            return candidates.first { $0.isWholeGrain } ?? defaultFlour(of: grain)
        }
        if grain == .durum, semolinaWords.contains(where: key.contains) {
            return candidates.first { $0.milling == .semolina }
        }
        if let number = firstNumber(typeExpression, in: key) {
            return nearest(to: Milling.type(number).ashKey, among: candidates, preferGerman: true)
        }
        if let number = firstNumber(frenchExpression, in: key) {
            if let exact = candidates.first(where: { $0.milling == .french(number) }) { return exact }
            return nearest(to: Milling.french(number).ashKey, among: candidates, preferGerman: true)
        }
        // Swiss names.
        if key.contains("ruchmehl")      { return nearest(to: 1050, among: candidates, preferGerman: true) }
        if key.contains("halbweiss")     { return nearest(to: 812,  among: candidates, preferGerman: true) }
        if key.contains("weissmehl") || key.contains("zopfmehl") { return nearest(to: 550, among: candidates, preferGerman: true) }
        if lightWords.contains(where: key.contains) {
            return candidates.first { $0.milling == .light } ?? nearest(to: Milling.light.ashKey, among: candidates, preferGerman: true)
        }
        return defaultFlour(of: grain)
    }

    private static func firstNumber(_ expression: NSRegularExpression?, in key: String) -> Int? {
        guard let expression,
              let match = expression.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)),
              let range = Range(match.range(at: 1), in: key)
        else { return nil }
        return Int(key[range])
    }

    /// The candidate whose milling lies closest on the ash scale. German
    /// types win a tie over French ones unless the line was French itself.
    private static func nearest(to ashKey: Int, among candidates: [Flour], preferGerman: Bool) -> Flour {
        let pool = candidates.filter { $0.milling != .semolina }
        return pool.min { a, b in
            let da = abs(a.milling.ashKey - ashKey)
            let db = abs(b.milling.ashKey - ashKey)
            if da != db { return da < db }
            let aGerman: Bool
            if case .french = a.milling { aGerman = false } else { aGerman = true }
            return aGerman == preferGerman
        } ?? candidates[0]
    }

    private static func comparisonKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
    }

    // MARK: - Water

    /// Grams of water to add (negative: to take away) when `grams` of `from`
    /// become the same weight of `to`.
    static func waterDelta(grams: Double, from: Flour, to: Flour) -> Double {
        grams * (to.extraWater - from.extraWater)
    }

    // MARK: - Hints

    enum Hint: Hashable, Identifiable {
        case speltHandling
        case speltSoaker
        case ryeAcidify
        case ryeMixOnly
        case emmer
        case einkorn
        case durumAutolyse
        case wholeGrainSoak
        case wheatKnead
        case addWaterGradually

        var id: Self { self }
    }

    /// The rye share of all flour from which the dough wants acidifying.
    static let ryeAcidifyShare = 0.2

    /// What changes in the handling, in the order worth reading. `ryeShareAfter`
    /// is the rye share of all flour once the swap is made; nil without a
    /// recipe, when only the general rye rule can be given.
    static func hints(from: Flour, to: Flour, ryeShareAfter: Double?) -> [Hint] {
        var hints: [Hint] = []

        if to.grain != from.grain {
            switch to.grain {
            case .spelt:   hints.append(.speltHandling)
            case .emmer:   hints.append(.emmer)
            case .einkorn: hints.append(.einkorn)
            case .durum:   hints.append(.durumAutolyse)
            case .wheat:   hints.append(.wheatKnead)
            case .rye:     break
            }
        }
        if to.grain == .rye {
            if let share = ryeShareAfter, share > 0.5 {
                hints.append(.ryeMixOnly)
            } else if ryeShareAfter == nil || ryeShareAfter! >= ryeAcidifyShare || from.grain != .rye {
                hints.append(.ryeAcidify)
            }
        }
        if to.grain == .spelt, to.grain != from.grain || to.isWholeGrain {
            hints.append(.speltSoaker)
        }
        if to.isWholeGrain, !from.isWholeGrain {
            hints.append(.wholeGrainSoak)
        }
        // Only for water that is added; holding some back needs no advice.
        if to.extraWater - from.extraWater >= 0.03 {
            hints.append(.addWaterGradually)
        }
        return hints
    }

    // MARK: - Applying to a recipe

    struct Applied: Equatable {
        var recipe: RecipeExportData
        let source: Flour
        let target: Flour
        /// Whole grams, as written into the liquid line.
        let waterDelta: Double
        /// False when the component has no poured liquid to change — the
        /// swap is still made, the liquid is the baker's to adjust.
        let waterAdjusted: Bool
        /// The line that was moved: "Wasser", or the milk, buttermilk or
        /// beer that stands in for it in a component without water.
        let adjustedLiquidName: String?
    }

    /// The recipe with one flour line swapped and the liquid of the same
    /// component moved by what the new flour binds — plain water when there
    /// is some, otherwise the component's poured liquid, which the baker's
    /// convention counts as water anyway. Nothing else changes; the copy
    /// gets the target flour added to its name.
    static func apply(to recipe: RecipeExportData, componentIndex: Int, ingredientIndex: Int, target: Flour,
                      on date: Date = Date()) -> Applied? {
        guard recipe.components.indices.contains(componentIndex),
              recipe.components[componentIndex].ingredients.indices.contains(ingredientIndex)
        else { return nil }

        var copy = recipe
        var ingredient = copy.components[componentIndex].ingredients[ingredientIndex]
        guard let source = recognize(ingredient.name) else { return nil }

        let grams = ingredient.normWeight > 0 ? ingredient.normWeight : ingredient.weight
        let delta = waterDelta(grams: grams, from: source, to: target).rounded()

        ingredient.name = target.ingredientName
        copy.components[componentIndex].ingredients[ingredientIndex] = ingredient

        var waterAdjusted = false
        var adjustedLiquidName: String?
        let lines = copy.components[componentIndex].ingredients
        if delta != 0,
           let liquidIndex = lines.firstIndex(where: isPlainWater) ?? lines.firstIndex(where: isPouredLiquid) {
            var liquid = lines[liquidIndex]
            liquid.weight = max(0, liquid.weight + delta)
            if liquid.normWeight > 0 {
                liquid.normWeight = max(0, liquid.normWeight + delta)
            }
            copy.components[componentIndex].ingredients[liquidIndex] = liquid
            copy.totalWeight = max(0, copy.totalWeight + delta)
            waterAdjusted = true
            adjustedLiquidName = IngredientNameNormalizer.displayName(liquid.name)
        }

        copy.name = AdjustedRecipe.name(original: recipe.name, adjustment: target.title, on: date)
        return Applied(recipe: copy, source: source, target: target,
                       waterDelta: delta, waterAdjusted: waterAdjusted,
                       adjustedLiquidName: adjustedLiquidName)
    }

    /// Any liquid the dough yield counts as water — water, milk, beer —
    /// measured in grams or millilitres.
    static func isPouredLiquid(_ ingredient: RecipeExportIngredient) -> Bool {
        guard DoughComposition.classify(ingredient.name) == .water else { return false }
        let unit = (ingredient.unit ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return unit.isEmpty || unit.hasPrefix("g") || unit.hasPrefix("ml")
    }

    /// Water itself, the line to prefer when the component has one.
    static func isPlainWater(_ ingredient: RecipeExportIngredient) -> Bool {
        guard isPouredLiquid(ingredient) else { return false }
        let key = comparisonKey(ingredient.name)
        return ["wasser", "water", "eau"].contains(where: key.contains)
    }

    /// Rye as a share of all flour in the recipe, 0 when there is no flour.
    static func ryeShare(in recipe: RecipeExportData) -> Double {
        var flour = 0.0
        var rye = 0.0
        for component in recipe.components {
            for ingredient in component.ingredients {
                guard let found = recognize(ingredient.name) else { continue }
                let grams = ingredient.normWeight > 0 ? ingredient.normWeight : ingredient.weight
                flour += grams
                if found.grain == .rye { rye += grams }
            }
        }
        return flour > 0 ? rye / flour : 0
    }
}

// MARK: - Dough yield of an export-model recipe

extension DoughComposition {
    static func components(of recipe: RecipeExportData) -> [Component] {
        recipe.components.map { component in
            Component(name: component.name, ingredients: component.ingredients.map { ingredient in
                Ingredient(name: ingredient.name,
                           grams: ingredient.normWeight > 0 ? ingredient.normWeight : ingredient.weight,
                           weight: ingredient.weight,
                           numerator: ingredient.num,
                           denominator: ingredient.denom)
            })
        }
    }
}
