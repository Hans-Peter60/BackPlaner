//
//  KitchenShoppingLines.swift
//  BakePlannerCore
//
//  CookPlanner's shopping list as one line per thing to buy. A dish lists
//  its ingredients per component — butter for the meat, butter for the
//  cabbage, butter for the mushrooms — which is right for cooking and
//  wrong for shopping. Here the ingredients that are the same thing
//  (IngredientNameNormalizer.comparisonKey, as BakePlanner's list and
//  pantry compare names) become one line with their amounts added up:
//  grams with kilograms, millilitres with litres, pieces with pieces, and
//  any other unit with the same unit; what cannot be added stands side by
//  side ("50 g + 1 EL"). An ingredient without an amount ("Salz") appears
//  once. The component lists stay as they are.
//

import Foundation

extension KitchenShoppingList {

    public struct Line: Identifiable, Equatable, Sendable {
        /// The comparison key of the name.
        public let id: String
        /// The name as the dish first gives it.
        public let name: String
        /// The added-up amounts, one per unit family, in the dish's order.
        public let amounts: [Quantity]
        /// The ingredients the line stands for, ticked together.
        public let ingredientIDs: [String]
        /// The components that use it, in the dish's order.
        public let components: [String]
        /// The remark, when the line is a single ingredient that has one.
        public let note: String
        /// Pieces added up from single ones ("1 Knoblauchzehe" three times):
        /// the singular name needs its plural.
        public var needsPlural = false

        /// "70 g", "2 EL", "50 g + 1 EL", "" without any amount.
        public func amountText(locale: Locale = AppSettings.locale) -> String {
            amounts.map { $0.text(locale: locale) }.joined(separator: " + ")
        }

        /// "70 g Butter", "Salz", "1 Schalotte (klein)".
        public func text(locale: Locale = AppSettings.locale) -> String {
            let quantity = amountText(locale: locale)
            let shown = needsPlural && locale.language.languageCode == .german ? Self.germanPlural(name) : name
            var text = quantity.isEmpty ? shown : "\(quantity) \(shown)"
            if !note.isEmpty { text += " (\(note))" }
            return text
        }

        /// The common German plurals of things counted in a kitchen:
        /// "Zehe" → "Zehen", "Zwiebel" → "Zwiebeln", "Ei" → "Eier"; any
        /// other ending is left as it is rather than guessed.
        static func germanPlural(_ name: String) -> String {
            if name == "Ei" { return "Eier" }
            if name.hasSuffix("e") { return name + "n" }
            if name.hasSuffix("el") { return name + "n" }
            return name
        }
    }

    /// An amount with its unit, as it is added up.
    public struct Quantity: Equatable, Sendable {
        public let value: Double
        public let unit: String

        /// Grams from a kilo on as kilograms, millilitres from a litre on as litres.
        public func text(locale: Locale) -> String {
            var value = value, unit = unit
            if unit == "g", value >= 1_000 { value /= 1_000; unit = "kg" }
            if unit == "ml", value >= 1_000 { value /= 1_000; unit = "l" }
            let number = value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
            return unit.isEmpty ? number : "\(number) \(unit)"
        }
    }

    /// The units that are the same measure, and the factor to their base.
    private static func family(of unit: String) -> (key: String, base: String, factor: Double) {
        let folded = unit.trimmingCharacters(in: .whitespaces).lowercased()
        switch folded {
        case "g", "gr", "gramm": return ("weight", "g", 1)
        case "kg", "kilo", "kilogramm": return ("weight", "g", 1_000)
        case "ml": return ("volume", "ml", 1)
        case "cl": return ("volume", "ml", 10)
        case "dl": return ("volume", "ml", 100)
        case "l", "liter": return ("volume", "ml", 1_000)
        case "", "stück", "stk", "stk.", "st", "st.": return ("count", "", 1)
        default: return ("unit:" + folded, unit.trimmingCharacters(in: .whitespaces), 1)
        }
    }

    /// One line per thing to buy, in the order the dish first names them.
    public static func lines(of dish: KitchenDish) -> [Line] {
        var order: [String] = []
        var grouped: [String: [KitchenIngredient]] = [:]
        for ingredient in groups(of: dish).flatMap(\.ingredients) {
            let key = IngredientNameNormalizer.comparisonKey(ingredient.name)
            let id = key.isEmpty ? ingredient.id : key
            if grouped[id] == nil { order.append(id) }
            grouped[id, default: []].append(ingredient)
        }
        return order.compactMap { id in
            guard let ingredients = grouped[id], let first = ingredients.first else { return nil }
            var families: [String] = []
            var sums: [String: (base: String, value: Double)] = [:]
            for ingredient in ingredients {
                guard let amount = ingredient.amount else { continue }
                let family = family(of: ingredient.unit)
                if sums[family.key] == nil { families.append(family.key) }
                sums[family.key] = (family.base, (sums[family.key]?.value ?? 0) + amount * family.factor)
            }
            var components: [String] = []
            for ingredient in ingredients where !ingredient.component.isEmpty && !components.contains(ingredient.component) {
                components.append(ingredient.component)
            }
            // A name the recipe already gives in the plural ("2 Knoblauchzehen") wins.
            let plural = ingredients.first { ($0.amount ?? 0) > 1 && family(of: $0.unit).key == "count" }
            let counted = sums["count"]?.value ?? 0
            var line = Line(id: id, name: plural?.name ?? first.name,
                        amounts: families.compactMap { sums[$0].map { Quantity(value: $0.value, unit: $0.base) } },
                        ingredientIDs: ingredients.map(\.id), components: components,
                        note: ingredients.count == 1 ? first.note : "")
            line.needsPlural = plural == nil && counted > 1 && families == ["count"]
            return line
        }
    }

    /// What is still to buy, one line per thing and nothing else; a line
    /// counts as at home when all its ingredients are.
    public static func missingLines(for dish: KitchenDish, available: Set<String>,
                                    locale: Locale = AppSettings.locale) -> String {
        lines(of: dish)
            .filter { !$0.ingredientIDs.allSatisfy(available.contains) }
            .map { $0.text(locale: locale) }
            .joined(separator: "\n")
    }
}
