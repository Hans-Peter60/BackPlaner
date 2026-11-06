//
//  DoughComposition.swift
//  BakePlannerCore
//
//  Dough yield (Teigausbeute, TA) and hydration of a recipe over all of its
//  components, with the flour and water hidden in a sourdough starter taken
//  apart by the starter's own TA. The baker's convention applies: every
//  poured liquid counts as water in full, seeds, flakes, fat and eggs do not
//  count at all, so the figures match what baking books print.
//

import Foundation

public enum DoughComposition {

    // MARK: - Input

    public struct Ingredient: Equatable {
        public let name: String
        /// Weight in grams after unit conversion (`normWeight`).
        public let grams: Double
        /// The weight as entered; zero for a row that stands for another
        /// component ("gesamter Sauerteig") or for a counted amount.
        public let weight: Double
        public let numerator: Int
        public let denominator: Int

        public init(name: String, grams: Double, weight: Double? = nil, numerator: Int = 0, denominator: Int = 0) {
            self.name        = name
            self.grams       = grams
            self.weight      = weight ?? grams
            self.numerator   = numerator
            self.denominator = denominator
        }
    }

    public struct Component: Equatable {
        public let name: String
        public let ingredients: [Ingredient]

        public init(name: String, ingredients: [Ingredient]) {
            self.name = name
            self.ingredients = ingredients
        }
    }

    public static func components(of recipe: RecipeFB) -> [Component] {
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

    /// The dough yields the user keeps his own starters at, for recipes that
    /// name an amount of starter but not its TA (Settings → Rezepte).
    public struct StarterYields: Equatable {
        public var sourdough: Double
        public var lievitoMadre: Double

        public init(sourdough: Double, lievitoMadre: Double) {
            self.sourdough = sourdough
            self.lievitoMadre = lievitoMadre
        }

        public static let standard = StarterYields(sourdough: 200, lievitoMadre: 150)

        public static var stored: StarterYields {
            StarterYields(sourdough: Double(AppSettings.storedStarterDoughYield),
                          lievitoMadre: Double(AppSettings.storedLievitoMadreDoughYield))
        }
    }

    // MARK: - Output

    public enum StarterKind: Equatable {
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
    public enum YieldSource: Equatable {
        /// Written into the ingredient's name: "Anstellgut (TA 200)".
        case name
        /// The user's setting for this kind of starter.
        case setting
        /// Fixed by the kind's definition (biga, poolish, pâte fermentée).
        case definition
    }

    /// An amount of starter and how it was split into flour and water.
    public struct StarterShare: Identifiable, Equatable {
        public let id: Int
        public let name: String
        public let grams: Double
        public let kind: StarterKind
        public let doughYield: Double
        public let source: YieldSource

        public var flour: Double { grams * 100 / doughYield }
        public var water: Double { grams - flour }
    }

    /// Flour and water a component brings in through its own ingredients,
    /// without what it takes over from other components.
    public struct ComponentShare: Identifiable, Equatable {
        public let id: Int
        public let name: String
        public let flour: Double
        public let water: Double

        public var doughYield: Double? { DoughComposition.doughYield(flour: flour, water: water) }
        public var hydration: Double? { flour > 0 ? water * 100 / flour : nil }
    }

    /// A heavier ingredient that counts neither as flour nor as water.
    public struct Uncounted: Identifiable, Equatable {
        public let id: Int
        public let name: String
        public let grams: Double
    }

    public struct Result: Equatable {
        public let flour: Double
        public let water: Double
        public let components: [ComponentShare]
        public let starters: [StarterShare]
        public let uncounted: [Uncounted]
        /// The flour that ferments before the main dough is mixed: in the
        /// preferments (Sauerteig, Poolish, Biga, Vorteig …) the main dough
        /// takes over, and in the starter ingredients themselves.
        public let prefermentedFlour: Double
        /// Salt and yeast over the whole recipe, in grams, for the
        /// plausibility hints; 0 when none was found.
        public let salt: Double
        public let freshYeast: Double
        public let dryYeast: Double

        public var doughYield: Double { DoughComposition.doughYield(flour: flour, water: water) ?? 0 }
        public var hydration: Double { water * 100 / flour }
        /// Pre-fermented flour as a percentage of all flour.
        public var prefermentedShare: Double { flour > 0 ? prefermentedFlour * 100 / flour : 0 }
        /// Baker's percentages: the share of the flour.
        public var saltShare: Double { flour > 0 ? salt * 100 / flour : 0 }
        public var freshYeastShare: Double { flour > 0 ? freshYeast * 100 / flour : 0 }
        public var dryYeastShare: Double { flour > 0 ? dryYeast * 100 / flour : 0 }
    }

    /// TA = (flour + water) / flour × 100; nil without flour. Multiplied
    /// before dividing so round figures stay round.
    public static func doughYield(flour: Double, water: Double) -> Double? {
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
    public static func compute(_ components: [Component], starterYields: StarterYields = .stored) -> Result? {
        guard !components.isEmpty else { return nil }

        struct Analysis {
            var flour = 0.0
            var water = 0.0
            var grams = 0.0
            /// Flour of the starter ingredients: fermented before this
            /// component was mixed.
            var starterFlour = 0.0
            var salt = 0.0
            var freshYeast = 0.0
            var dryYeast = 0.0
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
                    analyses[index].starterFlour += share.flour
                    starters.append(share)

                case .other:
                    if isSalt(ingredient.name) {
                        analyses[index].salt += grams
                    } else if let yeast = yeastKind(ingredient.name) {
                        switch yeast {
                        case .fresh: analyses[index].freshYeast += grams
                        case .dry: analyses[index].dryYeast += grams
                        }
                    }
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

        struct Contribution {
            var flour = 0.0
            var water = 0.0
            var prefermented = 0.0
            var salt = 0.0
            var freshYeast = 0.0
            var dryYeast = 0.0
        }

        /// A component taken over by another is a preferment when its
        /// name says so; a soaker ("Brühstück") is taken over as well but
        /// ferments nothing.
        func contribution(of index: Int, visited: Set<Int>) -> Contribution {
            var total = Contribution(flour: analyses[index].flour, water: analyses[index].water,
                                     prefermented: analyses[index].starterFlour,
                                     salt: analyses[index].salt, freshYeast: analyses[index].freshYeast,
                                     dryYeast: analyses[index].dryYeast)
            for reference in analyses[index].references where !visited.contains(reference.index) {
                let share = fraction(of: reference, usedBy: index)
                let child = contribution(of: reference.index, visited: visited.union([index]))
                total.flour += share * child.flour
                total.water += share * child.water
                total.prefermented += share * (isPrefermentName(components[reference.index].name) ? child.flour : child.prefermented)
                total.salt += share * child.salt
                total.freshYeast += share * child.freshYeast
                total.dryYeast += share * child.dryYeast
            }
            return total
        }

        let referenced = Set(analyses.flatMap { $0.references.map(\.index) })
        var roots = components.indices.filter { !referenced.contains($0) }
        if roots.isEmpty { roots = Array(components.indices) }

        var sum = Contribution()
        for root in roots {
            let total = contribution(of: root, visited: [])
            sum.flour += total.flour
            sum.water += total.water
            // A preferment nobody names in the main dough ("Vorteig" beside
            // "Hauptteig") is a root of its own; its flour is pre-fermented
            // all the same — unless the recipe is nothing but the starter.
            sum.prefermented += roots.count > 1 && isPrefermentName(components[root].name) ? total.flour : total.prefermented
            sum.salt += total.salt
            sum.freshYeast += total.freshYeast
            sum.dryYeast += total.dryYeast
        }
        let flour = sum.flour
        let water = sum.water

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
                      uncounted: Array(uncounted),
                      prefermentedFlour: min(sum.prefermented, flour),
                      salt: sum.salt,
                      freshYeast: sum.freshYeast,
                      dryYeast: sum.dryYeast)
    }

    // MARK: - Classification

    public enum Class: Equatable {
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
    /// Dry goods and non-liquids that merely contain a liquid's word —
    /// "épeautre" (spelt) carries "eau" in the middle of it.
    private static let notWaterWords = ["pulver", "powder", "poudre", "trocken", "weinstein", "vinaigre", "essig", "vinegar", "epeautre"]
    /// Dried or extracted sourdough is a flavouring, not a starter.
    private static let notStarterWords = ["pulver", "powder", "poudre", "trocken", "extrakt", "extract", "getrocknet"]
    private static let lievitoMadreWords = ["lievito madre", "pasta madre", "licoli", "li.co.li"]
    private static let pateFermenteeWords = ["pate fermentee", "alter teig", "old dough", "fermentierter teig"]
    private static let bigaWords = ["biga"]
    private static let poolishWords = ["poolish"]
    private static let sourdoughWords = ["anstellgut", "sauerteig", "levain", "sourdough", "starter", "madre"]
    /// Ingredients that are expected not to count and would only add noise.
    private static let unremarkableWords = ["salz", "salt", "sel", "hefe", "yeast", "levure", "zucker", "sugar", "sucre", "honig", "honey", "miel", "malz", "malt", "sirup", "syrup", "sirop"]

    public static func classify(_ name: String) -> Class {
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

    public static func isFlour(_ name: String) -> Bool {
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

    // MARK: - Preferments, salt and yeast

    /// A component whose name says it ferments before the main dough.
    private static let prefermentComponentWords = ["vorteig", "preferment", "pre-ferment", "sponge", "sauer", "levain",
                                                   "poolish", "biga", "pate fermentee", "madre", "starter", "anstellgut",
                                                   "alter teig", "old dough"]

    public static func isPrefermentName(_ name: String) -> Bool {
        let key = comparisonKey(name)
        return prefermentComponentWords.contains(where: key.contains)
    }

    /// Salt, "Meersalz" included; not salted butter, not "Sellerie".
    private static let saltExpression = try? NSRegularExpression(pattern: #"salz\b|\bsalt\b|\bsel\b|\bsale\b"#)

    public static func isSalt(_ name: String) -> Bool {
        let key = comparisonKey(name)
        guard let expression = saltExpression else { return false }
        return expression.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
    }

    public enum YeastKind: Equatable {
        case fresh
        case dry
    }

    private static let yeastWords = ["hefe", "yeast", "levure", "lievito di birra"]
    /// Baking powder, yeast flakes and yeast water are no yeast.
    private static let notYeastWords = ["backpulver", "baking powder", "levure chimique", "flocken", "flakes", "wasser", "water", "eau",
                                        "extrakt", "extract", "nahrung", "nutrient"]
    private static let dryYeastWords = ["trocken", "dry", "instant", "seche", "lyophilis", "granul"]

    /// Fresh or dry yeast, nil for anything else.
    public static func yeastKind(_ name: String) -> YeastKind? {
        let key = comparisonKey(name)
        guard yeastWords.contains(where: key.contains), !notYeastWords.contains(where: key.contains) else { return nil }
        return dryYeastWords.contains(where: key.contains) ? .dry : .fresh
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
    public static func doughYield(of kind: StarterKind, in name: String, yields: StarterYields) -> (Double, YieldSource) {
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
    public static func doughYield(in name: String) -> Double? {
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
