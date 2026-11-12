//
//  PantryReservations.swift
//  BakePlannerCore
//
//  The pantry's ledger. A plan reserves what its bread will use; the stock
//  itself stays what is physically there. Available = stock − reservations
//  of open plans. A plan that goes takes its reservations with it; a plan
//  that reaches its end turns them into real deductions. Every booking is
//  tied to a plan ID, so nothing is taken twice and nothing is lost.
//

import Foundation

/// What one open plan has reserved of one pantry item.
public struct StoredPantryReservation: Equatable, Identifiable, Sendable {
    /// The store's own key.
    public var id: String
    public var planID: UUID
    public var recipeName: String
    /// The pantry item's UUID (`StoredPantryItem.uuid`).
    public var itemID: String
    /// In the item's unit at the time of reserving.
    public var amount: Double
    public var unit: PantryUnit
    /// When the plan is finished — the moment the reservation becomes a
    /// deduction.
    public var planEnd: Date
    public var createdAt: Date

    public init(id: String, planID: UUID, recipeName: String, itemID: String, amount: Double, unit: PantryUnit,
                planEnd: Date, createdAt: Date = Date()) {
        self.id = id
        self.planID = planID
        self.recipeName = recipeName
        self.itemID = itemID
        self.amount = amount
        self.unit = unit
        self.planEnd = planEnd
        self.createdAt = createdAt
    }

    /// The reserved amount in grams or pieces.
    public var baseAmount: Double { amount * (unit.grams ?? 1) }
}

public protocol PantryReservationStore {
    func reservations() throws -> [StoredPantryReservation]
    func add(planID: UUID, recipeName: String, itemID: String, amount: Double, unit: PantryUnit, planEnd: Date) throws -> StoredPantryReservation
    /// Drops every reservation of the plan.
    func delete(planID: UUID) throws
    func delete(id: String) throws
}

/// A deduction that was made when a plan ended, kept so it can be undone.
public struct PantryBooking: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var recipeName: String
    public var itemID: String
    public var itemName: String
    public var amount: Double
    public var unit: PantryUnit

    public init(id: UUID = UUID(), date: Date, recipeName: String, itemID: String, itemName: String, amount: Double, unit: PantryUnit) {
        self.id = id
        self.date = date
        self.recipeName = recipeName
        self.itemID = itemID
        self.itemName = itemName
        self.amount = amount
        self.unit = unit
    }
}

public enum PantryLedger {

    /// What is reserved of each item, by the item's UUID, in grams or pieces.
    public static func reservedBase(_ reservations: [StoredPantryReservation]) -> [String: Double] {
        var result: [String: Double] = [:]
        for reservation in reservations {
            result[reservation.itemID, default: 0] += reservation.baseAmount
        }
        return result
    }

    /// The reserved amount of one item, in the item's unit.
    public static func reservedAmount(of item: StoredPantryItem, reservations: [StoredPantryReservation]) -> Double {
        let base = reservedBase(reservations)[item.uuid] ?? 0
        return base / (item.unit.grams ?? 1)
    }

    /// The items with what is still free of them: stock less the
    /// reservations, never below nothing. What the recipe card, the
    /// shopping list and the planners compare against.
    public static func available(_ items: [StoredPantryItem], reservations: [StoredPantryReservation]) -> [StoredPantryItem] {
        let reserved = reservedBase(reservations)
        return items.map { item in
            var free = item
            let base = max(0, item.baseAmount - (reserved[item.uuid] ?? 0))
            free.amount = base / (item.unit.grams ?? 1)
            return free
        }
    }

    /// Across several breads at once: what is missing of the available
    /// pantry, one need per ingredient with the shortfall summed up. Empty
    /// when everything is there.
    public static func shortfalls(for recipes: [(recipe: RecipeExportData, scale: Double)],
                                  available: [StoredPantryItem]) -> [PantryNeed] {
        var needs: [String: PantryNeed] = [:]
        var order: [String] = []
        for (recipe, scale) in recipes {
            for need in PantryMatcher.check(recipe, scale: scale, pantry: available).needs {
                let key = (need.isCounted ? "St|" : "g|") + IngredientNameNormalizer.comparisonKey(need.name)
                if let existing = needs[key] {
                    needs[key] = PantryNeed(name: existing.name, requiredBase: existing.requiredBase + need.requiredBase,
                                            availableBase: existing.availableBase, isCounted: existing.isCounted)
                } else {
                    order.append(key)
                    needs[key] = need
                }
            }
        }
        return order.compactMap { needs[$0] }.filter { !$0.isCovered }
    }

    /// The reservations whose plan has ended: due to become deductions.
    public static func dueForConversion(_ reservations: [StoredPantryReservation], now: Date = Date()) -> [StoredPantryReservation] {
        reservations.filter { $0.planEnd <= now }
    }

    /// The item after a reservation is converted: its stock less the
    /// reserved amount, never below nothing.
    public static func converted(_ item: StoredPantryItem, by reservation: StoredPantryReservation) -> StoredPantryItem {
        var result = item
        let base = max(0, item.baseAmount - reservation.baseAmount)
        result.amount = base / (item.unit.grams ?? 1)
        return result
    }
}
