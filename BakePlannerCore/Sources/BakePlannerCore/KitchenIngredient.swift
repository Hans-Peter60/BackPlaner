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
