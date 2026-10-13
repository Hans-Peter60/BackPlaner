//
//  ShoppingListCategory.swift
//  BackPlaner
//

import SwiftUI

/// The shelf an ingredient is found on, so a shopping list reads in the order
/// of a walk through the shop instead of alphabetically.
///
/// Decided from the name whenever the list is shown; nothing is stored. So
/// older lists get the grouping as well, and an entry whose name is corrected
/// simply moves to its shelf.
enum ShoppingListCategory: Int, CaseIterable, Identifiable {
    case flourAndGrain
    case dairyAndEggs
    case bakingSupplies
    case nutsSeedsDriedFruit
    case fruitAndVegetables
    case spicesAndHerbs
    case fatsAndLiquids
    case other

    var id: Int { rawValue }

    /// The heading above the group.
    var title: LocalizedStringKey {
        switch self {
        case .flourAndGrain:        return "Mehl & Getreide"
        case .dairyAndEggs:         return "Milchprodukte & Eier"
        case .bakingSupplies:       return "Backzutaten"
        case .nutsSeedsDriedFruit:  return "Nüsse, Saaten & Trockenfrüchte"
        case .fruitAndVegetables:   return "Obst & Gemüse"
        case .spicesAndHerbs:       return "Gewürze & Kräuter"
        case .fatsAndLiquids:       return "Öle, Fette & Flüssiges"
        case .other:                return "Sonstiges"
        }
    }

    var systemImage: String {
        switch self {
        case .flourAndGrain:        return "leaf"
        case .dairyAndEggs:         return "refrigerator"
        case .bakingSupplies:       return "birthday.cake"
        case .nutsSeedsDriedFruit:  return "allergens"
        case .fruitAndVegetables:   return "carrot"
        case .spicesAndHerbs:       return "sparkles"
        case .fatsAndLiquids:       return "drop.fill"
        case .other:                return "basket"
        }
    }

    /// One shelf of a list with the entries on it.
    struct Shelf<Item>: Identifiable {
        let category: ShoppingListCategory
        let items: [Item]
        var id: ShoppingListCategory { category }
    }

    /// The entries grouped by shelf, in the order of the shop, with the
    /// entries of each shelf sorted by name. Shelves without an entry are
    /// left out.
    static func shelves<Item>(_ items: [Item], name: (Item) -> String) -> [Shelf<Item>] {
        let grouped = Dictionary(grouping: items) { category(for: name($0)) }

        return allCases.compactMap { category in
            guard let entries = grouped[category], !entries.isEmpty else { return nil }
            let sorted = entries.sorted {
                name($0).localizedStandardCompare(name($1)) == .orderedAscending
            }
            return Shelf(category: category, items: sorted)
        }
    }

    // MARK: - Classification

    /// Patterns tried against the folded, lower-cased name (umlauts
    /// stripped, so "Nüsse" is matched as "nusse"). Plain words match
    /// anywhere in the name; `\b` is used where a word is also the start of
    /// something else ("Ei" in "Weizen", "Reis" in "Preiselbeeren").
    private struct Rule {
        let category: ShoppingListCategory
        let patterns: [String]
        /// Names containing one of these are not this category after all:
        /// "Weinstein" is not a wine, "Trockenhefe" not a liquid.
        var exceptions: [String] = []
    }

    /// Specific shelves come first: "Mandelmehl" is a nut, not a flour;
    /// "Erdnussbutter" is a nut, not a dairy product; "Apfelessig" is a
    /// liquid, not a fruit; "Kartoffelstärke" a starch, not a vegetable.
    private static let rules: [Rule] = [
        Rule(category: .fatsAndLiquids,
             patterns: [#"ol\b"#, "oel", "oil", "huile", "schmalz", "margarine", "essig", "vinegar", "vinaigre",
                        #"\bbier\b"#, "malzbier", #"\bbeer\b"#, "biere", "wein", "wine", #"\bvin\b"#, "saft", "juice", #"\bjus\b"#],
             exceptions: ["weinstein", "pulver", "powder", "poudre", "trocken"]),
        Rule(category: .nutsSeedsDriedFruit,
             patterns: ["nuss", "nusse", "nuts", "noix", "mandel", "almond", "amande", "noisette", "cashew", "pistazie", "pistachio",
                        "sesam", "leinsamen", "leinsaat", "flaxseed", "sonnenblumenkern", "kurbiskern", "pinienkern", "kerne", "chia", "mohn", "poppy", "pavot",
                        "hanf", "kokos", "coconut", "noix de coco", "saat", "samen", "seed", "graine",
                        "rosinen", "sultaninen", "korinthen", "raisin", "cranberr", "dattel", "date", "datte", "feige", "fig", "figue",
                        "trockenfrucht", "trockenobst", "dorr", "getrocknet", "dried", "sech"]),
        Rule(category: .dairyAndEggs,
             patterns: [#"\bei\b"#, #"\beier\b"#, "eigelb", "eiweiss", "eiweiß", "eiklar", "vollei", #"\begg"#, "oeuf",
                        "milch", "milk", "lait", "butter", "beurre", "sahne", "rahm", "cream", "creme", "quark", "joghurt", "yoghurt", "yogurt", "yaourt",
                        "kase", "cheese", "fromage", "schmand", "mascarpone", "ricotta", "kefir", "molke", "whey"]),
        Rule(category: .bakingSupplies,
             patterns: ["hefe", "yeast", "levure", "backpulver", "baking powder", "levure chimique", "natron", "soda", "weinstein",
                        "zucker", "sugar", "sucre", "honig", "honey", #"\bmiel\b"#, "sirup", "syrup", "sirop", "malz", "malt",
                        "vanill", "kakao", "cocoa", "cacao", "schoko", "chocolat", "gelatine", "pudding", "marzipan", "lecithin", "gluten",
                        "backferment", "aroma", "streusel", "dekor", "glasur"]),
        Rule(category: .spicesAndHerbs,
             patterns: ["gewurz", "spice", "epice", "salz", "salt", #"\bsel\b"#, "pfeffer", "pepper", "poivre",
                        "kummel", "caraway", "cumin", "carvi", "koriander", "coriander", "fenchel", "fennel", "fenouil", "anis",
                        "zimt", "cinnamon", "cannelle", "kardamom", "cardamom", "muskat", "nutmeg", "nelke", "clove", "chili", "paprika", "curry", "ingwer", "ginger",
                        "krauter", "herb", "rosmarin", "rosemary", "thymian", "thym", "oregano", "basilikum", "basil", "petersilie", "schnittlauch", "dill"]),
        Rule(category: .flourAndGrain,
             patterns: ["mehl", "flour", "farine", "schrot", "griess", "grieß", "dunst", "semola", "semolina", "semoule",
                        "flocken", "flakes", "flocons", "kleie", "bran", "korner", "getreide", "grain", #"\breis\b"#, #"\brice\b"#, #"\briz\b"#,
                        "starke", "starch", "amidon", "hafer", "oat", "avoine", "dinkel", "spelt", "epeautre", "roggen", "rye", "seigle",
                        "weizen", "wheat", "gerste", "barley", "hirse", "millet", "quinoa", "amaranth", "polenta", #"\bmais\b"#, "couscous", "bulgur",
                        "vollkorn", "altbrot", "brosel", "paniermehl", "zwieback", "knacke", "breadcrumb", "chapelure"]),
        Rule(category: .fruitAndVegetables,
             patterns: ["apfel", "apple", "pomme", "birne", "pear", "poire", "banane", "banana", "zitron", "lemon", "citron", "limette", "lime",
                        "orange", "beere", "berry", "berries", "kirsch", "cherry", "cerise", "pflaume", "zwetschg", "plum", "prune", "aprikose", "apricot", "abricot",
                        "pfirsich", "peach", "rhabarber", "rhubarb", "traube", "grape", "ananas", "mango",
                        "zwiebel", "onion", "oignon", "knoblauch", "garlic", #"\bail\b"#, "kartoffel", "potato", "mohre", "mohren", "karotte", "carrot", "carotte",
                        "kurbis", "pumpkin", "courge", "zucchini", "courgette", "tomate", "tomato", "spinat", "spinach", "lauch", "leek", "poireau",
                        "sellerie", "celery", "paprikaschote", "oliven", "olive", "gemuse", "vegetable", "legume"])
    ]

    /// The shelf an ingredient belongs on, by its name.
    static func category(for name: String) -> ShoppingListCategory {
        let key = IngredientNameNormalizer.comparisonKey(name)
        guard !key.isEmpty else { return .other }

        for rule in rules {
            guard rule.patterns.contains(where: { matches(key, $0) }) else { continue }
            if rule.exceptions.contains(where: { key.contains($0) }) { continue }
            return rule.category
        }
        return .other
    }

    private static func matches(_ key: String, _ pattern: String) -> Bool {
        if pattern.contains("\\") {
            return key.range(of: pattern, options: [.regularExpression]) != nil
        }
        return key.contains(pattern)
    }
}
