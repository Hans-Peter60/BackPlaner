//
//  PantryStore.swift
//  BakePlannerCore
//
//  The pantry: what is in the house — flours, seeds, yeast — with how much
//  and until when. Kept behind a protocol like the other stores: Core Data
//  on iOS, SQLite on Android, in memory for the contract.
//

import Foundation

/// How a pantry amount is counted. Deliberately small: a bag of flour is
/// weighed, eggs are counted; the recipe's own units are converted to
/// grams or pieces when the two are compared.
public enum PantryUnit: String, CaseIterable, Codable, Identifiable, Sendable {
    case gram = "g"
    case kilogram = "kg"
    case piece = "St"

    public var id: String { rawValue }

    /// Grams per unit for the weighed ones; nil for pieces.
    public var grams: Double? {
        switch self {
        case .gram: return 1
        case .kilogram: return 1_000
        case .piece: return nil
        }
    }

    /// The unit a stored abbreviation means; grams when it is unknown.
    public init(stored: String?) {
        self = PantryUnit(rawValue: stored ?? "") ?? .gram
    }
}

/// One thing in the pantry as a store holds it.
public struct StoredPantryItem: Equatable, Identifiable, Sendable {
    /// The store's own key.
    public var id: String
    public var name: String
    public var amount: Double
    public var unit: PantryUnit
    /// The best-before date on the packet, when noted.
    public var bestBefore: Date?
    public var note: String
    /// When the amount was last set — the shelf-life view tells how long a
    /// packet has been open from it.
    public var updatedAt: Date
    /// The item's identity across devices (its UUID), which reservations
    /// refer to; the store key `id` is this device's handle only.
    public var uuid: String

    public init(id: String, name: String, amount: Double, unit: PantryUnit, bestBefore: Date? = nil,
                note: String = "", updatedAt: Date = Date(), uuid: String? = nil) {
        self.id = id
        self.name = name
        self.amount = amount
        self.unit = unit
        self.bestBefore = bestBefore
        self.note = note
        self.updatedAt = updatedAt
        self.uuid = uuid ?? id
    }

    /// The amount in the base the recipes compare against: grams for
    /// weighed goods, the count for pieces.
    public var baseAmount: Double {
        amount * (unit.grams ?? 1)
    }

    /// Whether the item is counted rather than weighed.
    public var isCounted: Bool { unit == .piece }

    /// The content as every store keeps it: names and notes trimmed, no
    /// negative amounts.
    public var normalized: StoredPantryItem {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.amount = max(0, amount)
        return copy
    }
}

public enum PantryStoreError: Error, Equatable {
    case unknownItem(String)
    case emptyName
}

public protocol PantryStore {
    /// Every item, by name.
    func items() throws -> [StoredPantryItem]
    /// Adds an item; an empty name is refused.
    func add(name: String, amount: Double, unit: PantryUnit, bestBefore: Date?, note: String) throws -> StoredPantryItem
    /// Replaces name, amount, unit, best-before and note of the item with
    /// this key; the key itself stays.
    func update(_ item: StoredPantryItem) throws
    func delete(id: String) throws
}

public extension PantryStore {
    /// The item whose name means the same ingredient, by the comparison key
    /// the shopping list merges with ("Weizenmehl 550" and "weizenmehl 550").
    func item(matching name: String) throws -> StoredPantryItem? {
        let key = IngredientNameNormalizer.comparisonKey(name)
        guard !key.isEmpty else { return nil }
        return try items().first { IngredientNameNormalizer.comparisonKey($0.name) == key }
    }

    /// Puts a bought amount into the pantry: onto the item of the same name
    /// when the units agree, as a new item otherwise. Returns what holds it.
    @discardableResult
    func receive(name: String, amount: Double, unit: PantryUnit, bestBefore: Date? = nil) throws -> StoredPantryItem {
        if var existing = try item(matching: name) {
            // Grams onto a kilogram item and the other way round are
            // converted; pieces onto a weighed item (or vice versa) cannot be,
            // so they become an item of their own.
            if existing.unit == unit {
                existing.amount += amount
            } else if let have = existing.unit.grams, let add = unit.grams {
                existing.amount += amount * add / have
            } else {
                return try add(name: IngredientNameNormalizer.displayName(name), amount: amount, unit: unit,
                               bestBefore: bestBefore, note: "")
            }
            if let bestBefore { existing.bestBefore = bestBefore }
            try update(existing)
            return try items().first { $0.id == existing.id } ?? existing
        }
        return try add(name: IngredientNameNormalizer.displayName(name), amount: amount, unit: unit,
                       bestBefore: bestBefore, note: "")
    }
}
