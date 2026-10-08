//
//  DoughComposition.swift
//  BackPlaner
//
//  Dough yield (Teigausbeute, TA) and hydration of a recipe over all of its
//  components, with the flour and water hidden in a sourdough starter taken
//  apart by the starter's own TA. The baker's convention applies: every
//  poured liquid counts as water in full, seeds, flakes, fat and eggs do not
//  count at all, so the figures match what baking books print.
//

import Foundation
import CoreData

enum DoughComposition {

    // MARK: - Input

    struct Ingredient: Equatable {
        let name: String
        /// Weight in grams after unit conversion (`normWeight`).
        let grams: Double
        /// The weight as entered; zero for a row that stands for another
        /// component ("gesamter Sauerteig") or for a counted amount.
        let weight: Double
        let numerator: Int
        let denominator: Int

        init(name: String, grams: Double, weight: Double? = nil, numerator: Int = 0, denominator: Int = 0) {
            self.name        = name
            self.grams       = grams
            self.weight      = weight ?? grams
            self.numerator   = numerator
            self.denominator = denominator
        }
    }

    struct Component: Equatable {
        let name: String
        let ingredients: [Ingredient]
    }

    static func components(of recipe: RecipeFB) -> [Component] {
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

    static func components(of recipe: Recipe) -> [Component] {
        recipe.componentsArray.map { component in
            Component(name: component.name, ingredients: component.ingredientsArray.map { ingredient in
                Ingredient(name: ingredient.name,
                           grams: ingredient.normWeight > 0 ? ingredient.normWeight : ingredient.weight,
                           weight: ingredient.weight,
                           numerator: ingredient.num,
                           denominator: ingredient.denom)
            })
        }
    }

    /// The dough yields the user keeps his own starters at, for recipes that
    /// name an amount of starter but not its TA (Settings → Rezepte).
    struct StarterYields: Equatable {
        var sourdough: Double
        var lievitoMadre: Double

        static let standard = StarterYields(sourdough: 200, lievitoMadre: 150)

        static var stored: StarterYields {
            StarterYields(sourdough: Double(AppSettings.storedStarterDoughYield),
                          lievitoMadre: Double(AppSettings.storedLievitoMadreDoughYield))
        }
    }

    // MARK: - Output

    enum StarterKind: Equatable {
        case sourdough
        case lievitoMadre
        /// A piece of yesterday's dough, about TA 165 by definition.
        case pateFermentee
        /// Stiff Italian preferment, TA 150 by definition.
        case biga
        /// Liquid preferment of equal parts flour and water, TA 200.
        case poolish
    }

    /// Where a starter's dough yield came from.
    enum YieldSource: Equatable {
        /// Written into the ingredient's name: "Anstellgut (TA 200)".
        case name
        /// The user's setting for this kind of starter.
        case setting
        /// Fixed by the kind's definition (biga, poolish, pâte fermentée).
        case definition
    }

    /// An amount of starter and how it was split into flour and water.
    struct StarterShare: Identifiable, Equatable {
        let id: Int
        let name: String
        let grams: Double
        let kind: StarterKind
        let doughYield: Double
        let source: YieldSource

        var flour: Double { grams * 100 / doughYield }
        var water: Double { grams - flour }
    }

    /// Flour and water a component brings in through its own ingredients,
    /// without what it takes over from other components.
    struct ComponentShare: Identifiable, Equatable {
        let id: Int
        let name: String
        let flour: Double
        let water: Double

        var doughYield: Double? { DoughComposition.doughYield(flour: flour, water: water) }
        var hydration: Double? { flour > 0 ? water * 100 / flour : nil }
    }

    /// A heavier ingredient that counts neither as flour nor as water.
    struct Uncounted: Identifiable, Equatable {
        let id: Int
        let name: String
        let grams: Double
    }

    struct Result: Equatable {
        let flour: Double
        let water: Double
        let components: [ComponentShare]
        let starters: [StarterShare]
        let uncounted: [Uncounted]

        var doughYield: Double { DoughComposition.doughYield(flour: flour, water: water) ?? 0 }
        var hydration: Double { water * 100 / flour }
    }

    /// TA = (flour + water) / flour × 100; nil without flour. Multiplied
    /// before dividing so round figures stay round.
    static func doughYield(flour: Double, water: Double) -> Double? {
        guard flour > 0 else { return nil }
        return (flour + water) * 100 / flour
    }

    // MARK: - Calculation

    /// Works out the recipe's composition, or nil when it contains no flour.
    ///
    /// A row that refers to another component is not counted itself; that
    /// component's content is pulled in instead — in full for "gesamter
    /// Sauerteig", in proportion for "200 g Sauerteig" when the component
    /// makes more than that. Components no other component uses are the
    /// final doughs and are summed; so a recipe that never names its
    /// preferments in the main dough still counts every component once.
    static func compute(_ components: [Component], starterYields: StarterYields = .stored) -> Result? {
        guard !components.isEmpty else { return nil }

        struct Analysis {
            var flour = 0.0
            var water = 0.0
            var grams = 0.0
            /// Components this one takes over, with the amount when only
            /// part of them is used.
            var references: [(index: Int, partGrams: Double?)] = []
        }

        let componentNames = components.map(\.name)
        var analyses = [Analysis](repeating: Analysis(), count: components.count)
        var shares: [ComponentShare] = []
        var starters: [StarterShare] = []
        var others: [Uncounted] = []

        for (index, component) in components.enumerated() {
            for ingredient in component.ingredients {
                if let target = ComponentProductMatcher.referencedComponent(
                    name: ingredient.name,
                    weight: ingredient.weight,
                    numerator: ingredient.numerator,
                    denominator: ingredient.denominator,
                    componentNames: componentNames
                ), target != index {
                    analyses[index].references.append((target, ingredient.weight > 0 ? ingredient.grams : nil))
                    continue
                }

                let grams = ingredient.grams
                guard grams > 0 else { continue }
                analyses[index].grams += grams

                switch classify(ingredient.name) {
                case .flour:
                    analyses[index].flour += grams

                case .water:
                    analyses[index].water += grams

                case .starter(let kind):
                    let (yield, source) = doughYield(of: kind, in: ingredient.name, yields: starterYields)
                    let share = StarterShare(id: starters.count,
                                             name: IngredientNameNormalizer.displayName(ingredient.name),
                                             grams: grams,
                                             kind: kind,
                                             doughYield: yield,
                                             source: source)
                    analyses[index].flour += share.flour
                    analyses[index].water += share.water
                    starters.append(share)

                case .other:
                    if isWorthListing(ingredient.name) {
                        others.append(Uncounted(id: others.count,
                                                name: IngredientNameNormalizer.displayName(ingredient.name),
                                                grams: grams))
                    }
                }
            }

            shares.append(ComponentShare(id: index,
                                         name: component.name,
                                         flour: analyses[index].flour,
                                         water: analyses[index].water))
        }

        // Everything a component weighs, including what it takes from others;
        // the base for scaling a partial use. `visited` guards against two
        // components that name each other.
        func totalGrams(of index: Int, visited: Set<Int>) -> Double {
            var total = analyses[index].grams
            for reference in analyses[index].references where !visited.contains(reference.index) {
                total += reference.partGrams ?? totalGrams(of: reference.index, visited: visited.union([index]))
            }
            return total
        }

        func fraction(of reference: (index: Int, partGrams: Double?), usedBy index: Int) -> Double {
            guard let partGrams = reference.partGrams else { return 1 }
            let total = totalGrams(of: reference.index, visited: [index])
            return total > 0 ? min(partGrams / total, 1) : 1
        }

        func contribution(of index: Int, visited: Set<Int>) -> (flour: Double, water: Double) {
            var flour = analyses[index].flour
            var water = analyses[index].water
            for reference in analyses[index].references where !visited.contains(reference.index) {
                let share = fraction(of: reference, usedBy: index)
                let child = contribution(of: reference.index, visited: visited.union([index]))
                flour += share * child.flour
                water += share * child.water
            }
            return (flour, water)
        }

        let referenced = Set(analyses.flatMap { $0.references.map(\.index) })
        var roots = components.indices.filter { !referenced.contains($0) }
        if roots.isEmpty { roots = Array(components.indices) }

        var flour = 0.0
        var water = 0.0
        for root in roots {
            let total = contribution(of: root, visited: [])
            flour += total.flour
            water += total.water
        }

        guard flour > 0 else { return nil }

        // Only amounts that would move the figures are worth a line.
        let threshold = max(10, flour * 0.03)
        let uncounted = others
            .filter { $0.grams >= threshold }
            .sorted { $0.grams > $1.grams }
            .prefix(6)

        return Result(flour: flour,
                      water: water,
                      components: shares,
                      starters: starters,
                      uncounted: Array(uncounted))
    }

    // MARK: - Classification

    enum Class: Equatable {
        case flour
        case water
        case starter(StarterKind)
        case other
    }

    /// Old bread in a scald ("Altbrot im Brühstück") counts as flour: dried
    /// and ground, it is flour that has already been baked once.
    private static let flourWords = ["mehl", "flour", "farine", "schrot", "griess", "grieß", "dunst", "semola", "semolina", "semoule",
                                     "altbrot", "restbrot", "brotreste", "brosel", "brösel", "old bread", "stale bread", "breadcrumb", "pain rassis", "chapelure"]
    /// Seeds, flakes and nuts that merely contain a flour's word
    /// ("Leinsamenschrot", "Mandelmehl"); bakers do not count them as flour.
    private static let notFlourWords = ["leinsamen", "leinschrot", "soja", "flocken", "kleie", "nuss", "nüsse", "mandel", "kokos"]
    /// Poured liquids, by the baker's convention all counted in full.
    private static let waterWords = ["wasser", "water", "eau", "milch", "milk", "lait", "buttermilk", "babeurre", "bier", "beer", "biere", "wein", "wine", "vin", "molke", "whey", "saft", "juice", "jus", "kefir"]
    /// Dry goods and non-liquids that merely contain a liquid's word.
    private static let notWaterWords = ["pulver", "powder", "poudre", "trocken", "weinstein", "vinaigre", "essig", "vinegar"]
    /// Dried or extracted sourdough is a flavouring, not a starter.
    private static let notStarterWords = ["pulver", "powder", "poudre", "trocken", "extrakt", "extract", "getrocknet"]
    private static let lievitoMadreWords = ["lievito madre", "pasta madre", "licoli", "li.co.li"]
    private static let pateFermenteeWords = ["pate fermentee", "alter teig", "old dough", "fermentierter teig"]
    private static let bigaWords = ["biga"]
    private static let poolishWords = ["poolish"]
    private static let sourdoughWords = ["anstellgut", "sauerteig", "levain", "sourdough", "starter", "madre"]
    /// Ingredients that are expected not to count and would only add noise.
    private static let unremarkableWords = ["salz", "salt", "sel", "hefe", "yeast", "levure", "zucker", "sugar", "sucre", "honig", "honey", "miel", "malz", "malt", "sirup", "syrup", "sirop"]

    static func classify(_ name: String) -> Class {
        let key = comparisonKey(name)

        if let kind = starterKind(in: key), !notStarterWords.contains(where: key.contains) {
            return .starter(kind)
        }
        if waterWords.contains(where: key.contains), !notWaterWords.contains(where: key.contains) {
            return .water
        }
        if flourWords.contains(where: key.contains), !notFlourWords.contains(where: key.contains) {
            return .flour
        }
        return .other
    }

    static func isFlour(_ name: String) -> Bool {
        classify(name) == .flour
    }

    private static func starterKind(in key: String) -> StarterKind? {
        if lievitoMadreWords.contains(where: key.contains) { return .lievitoMadre }
        if pateFermenteeWords.contains(where: key.contains) { return .pateFermentee }
        if bigaWords.contains(where: key.contains) { return .biga }
        if poolishWords.contains(where: key.contains) { return .poolish }
        if sourdoughWords.contains(where: key.contains) { return .sourdough }
        // "ASG" only as a word of its own; it is part of too many other words.
        if asgExpression?.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil { return .sourdough }
        return nil
    }

    private static func isWorthListing(_ name: String) -> Bool {
        let key = comparisonKey(name)
        return !unremarkableWords.contains(where: key.contains)
    }

    private static func comparisonKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
    }

    // MARK: - Starter dough yield

    private static let asgExpression = try? NSRegularExpression(pattern: #"\basg\b"#)
    /// "TA 200", "TA200", "TA: 200".
    private static let yieldExpression = try? NSRegularExpression(pattern: #"\bTA\s*:?\s*(\d{3})\b"#, options: [.caseInsensitive])
    /// "100 % Hydration", "80% hydratation".
    private static let hydrationExpression = try? NSRegularExpression(pattern: #"(\d{2,3})\s*%\s*hydr"#, options: [.caseInsensitive])

    /// The TA a starter is taken apart with: the one written into its name
    /// if there is one, otherwise the user's setting or the kind's definition.
    static func doughYield(of kind: StarterKind, in name: String, yields: StarterYields) -> (Double, YieldSource) {
        if let yield = doughYield(in: name) {
            return (yield, .name)
        }
        switch kind {
        case .sourdough:     return (yields.sourdough, .setting)
        case .lievitoMadre:  return (yields.lievitoMadre, .setting)
        case .pateFermentee: return (165, .definition)
        case .biga:          return (150, .definition)
        case .poolish:       return (200, .definition)
        }
    }

    /// A dough yield written into an ingredient name, or nil.
    static func doughYield(in name: String) -> Double? {
        let range = NSRange(name.startIndex..., in: name)

        if let match = yieldExpression?.firstMatch(in: name, range: range),
           let valueRange = Range(match.range(at: 1), in: name),
           let value = Double(name[valueRange]),
           (101...400).contains(value) {
            return value
        }

        if let match = hydrationExpression?.firstMatch(in: name, range: range),
           let valueRange = Range(match.range(at: 1), in: name),
           let percent = Double(name[valueRange]),
           (1...300).contains(percent) {
            return 100 + percent
        }

        return nil
    }
}
