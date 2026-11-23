//
//  KitchenIngredient.swift
//  BakePlannerCore
//
//  An ingredient of a CookPlanner dish: what to buy, and — through the
//  steps that name it — what to have at hand when a step begins. Amounts
//  and units stay as the recipe gives them; CookPlanner does not convert.
//

import Foundation

public struct KitchenIngredient: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public var name: String
    /// The quantity, nil when the recipe gives none ("Salz", "Pfeffer").
    public var amount: Double?
    /// "g", "ml", "EL", "Stück", "Zweig" …, or empty for a bare count.
    public var unit: String
    /// The part of the dish the ingredient belongs to; empty when the
    /// recipe does not say.
    public var component: String
    /// A remark the recipe adds: "fein gewürfelt", "zum Braten".
    public var note: String

    public init(id: String = UUID().uuidString, name: String, amount: Double? = nil, unit: String = "",
                component: String = "", note: String = "") {
        self.id = id
        self.name = name
        self.amount = amount.flatMap { $0 > 0 && $0.isFinite ? min($0, 100_000) : nil }
        self.unit = unit
        self.component = component
        self.note = note
    }

    /// The amount with its unit, as the shopping list and a step show it:
    /// "200 g", "1 Stück", "1,5 EL", or empty without an amount.
    public func amountText(locale: Locale = AppSettings.locale) -> String {
        guard let amount else { return unit }
        let number = amount.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    /// "200 g Kräuterseitlinge" or "Salz"; the note in parentheses.
    public func line(locale: Locale = AppSettings.locale) -> String {
        let quantity = amountText(locale: locale)
        var text = quantity.isEmpty ? name : "\(quantity) \(name)"
        if !note.isEmpty { text += " (\(note))" }
        return text
    }
}

extension KitchenDish {

    /// The ingredients of one component, in recipe order.
    public func ingredients(of component: String) -> [KitchenIngredient] {
        ingredients.filter { $0.component == component }
    }

    /// The ingredients a step names, in the dish's order.
    public func ingredients(for task: KitchenTask) -> [KitchenIngredient] {
        ingredients.filter { task.ingredientIDs.contains($0.id) }
    }
}

/// The shopping list of a dish: its ingredients by component, as text to
/// hand to a notes or reminders app.
public enum KitchenShoppingList {

    /// The components in the order the dish names them, then those only
    /// the ingredients name, then the ingredients without one (as "").
    public static func groups(of dish: KitchenDish) -> [(component: String, ingredients: [KitchenIngredient])] {
        var order = dish.components
        for ingredient in dish.ingredients where !ingredient.component.isEmpty && !order.contains(ingredient.component) {
            order.append(ingredient.component)
        }
        if dish.ingredients.contains(where: { $0.component.isEmpty }) { order.append("") }
        return order.compactMap { component in
            let ingredients = dish.ingredients(of: component)
            return ingredients.isEmpty ? nil : (component: component, ingredients: ingredients)
        }
    }

    /// What is still to buy, one ingredient per line and nothing else — the
    /// way Reminders makes one entry of every line, and a message reads it
    /// as a plain list. `available` are the ids the cook already has.
    public static func missingText(for dish: KitchenDish, available: Set<String>,
                                   locale: Locale = AppSettings.locale) -> String {
        groups(of: dish).flatMap(\.ingredients)
            .filter { !available.contains($0.id) }
            .map { $0.line(locale: locale) }
            .joined(separator: "\n")
    }

    /// The list as text: a heading per component, a dash per ingredient;
    /// `checked` ids are left out, as they are already in the basket.
    public static func text(for dish: KitchenDish, excluding checked: Set<String> = [],
                            locale: Locale = AppSettings.locale) -> String {
        var lines = [dish.name]
        for group in groups(of: dish) {
            let open = group.ingredients.filter { !checked.contains($0.id) }
            guard !open.isEmpty else { continue }
            lines.append("")
            if !group.component.isEmpty { lines.append(group.component) }
            lines += open.map { "- " + $0.line(locale: locale) }
        }
        return lines.joined(separator: "\n")
    }
}
