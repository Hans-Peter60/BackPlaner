//
//  PantryStoreContract.swift
//  BakePlannerCore
//
//  What every PantryStore must do, written once and checked against each
//  store: in memory, Core Data, SQLite. Each check takes a new, empty store
//  and throws ContractViolation when the store behaves differently.
//

import Foundation

public enum PantryStoreContract {

    public typealias Check = (PantryStore) throws -> Void

    public static let checks: [(name: String, run: Check)] = [
        ("an empty store has nothing", emptyStore),
        ("an item comes back as it was added, trimmed", addAndRead),
        ("items come by name", order),
        ("an update replaces every field but the key", update),
        ("a removed item is gone, the others stay", delete),
        ("an empty name is refused, unknown keys are reported", refusals),
        ("an item is found by the ingredient's name", matching),
        ("received amounts join the item of the same name, grams and kilograms converted", receiving),
    ]

    public static func emptyStore(_ store: PantryStore) throws {
        try expect(store.items().isEmpty, "an empty store has items")
    }

    public static func addAndRead(_ store: PantryStore) throws {
        let added = try store.add(name: "  Roggenmehl 1150 ", amount: 2.5, unit: .kilogram, bestBefore: day(30), note: " Mühle Meier\n")
        try expect(!added.id.isEmpty, "the new item has no key")
        try expect(added.name == "Roggenmehl 1150" && added.amount == 2.5 && added.unit == .kilogram
                   && added.bestBefore == day(30) && added.note == "Mühle Meier",
                   "add returns other content than it was given, or did not trim: \(added)")
        try expect(added.baseAmount == 2_500, "2.5 kg are not 2500 g")
        try expect(store.items() == [added], "the store's items differ from the one added")
        let negative = try store.add(name: "Hefe", amount: -3, unit: .piece, bestBefore: nil, note: "")
        try expect(negative.amount == 0 && negative.isCounted, "a negative amount was kept, or pieces are not counted")
    }

    public static func order(_ store: PantryStore) throws {
        let rye = try store.add(name: "Roggenmehl 1150", amount: 1_000, unit: .gram, bestBefore: nil, note: "")
        let spelt = try store.add(name: "Dinkelmehl 630", amount: 1_000, unit: .gram, bestBefore: nil, note: "")
        let yeast = try store.add(name: "hefe", amount: 2, unit: .piece, bestBefore: nil, note: "")
        try expect(store.items().map(\.id) == [spelt.id, yeast.id, rye.id], "items are not ordered by name")
    }

    public static func update(_ store: PantryStore) throws {
        let item = try store.add(name: "Weizenmehl 550", amount: 1_000, unit: .gram, bestBefore: day(10), note: "")
        let other = try store.add(name: "Sesam", amount: 200, unit: .gram, bestBefore: nil, note: "")
        var changed = item
        changed.name = " Weizenmehl 1050 "
        changed.amount = 0.75
        changed.unit = .kilogram
        changed.bestBefore = nil
        changed.note = " angebrochen "
        try store.update(changed)
        let stored = try store.items().first { $0.id == item.id }
        try expect(stored?.name == "Weizenmehl 1050" && stored?.amount == 0.75 && stored?.unit == .kilogram
                   && stored?.bestBefore == nil && stored?.note == "angebrochen",
                   "the update did not replace the fields, or did not trim: \(String(describing: stored))")
        try expect(stored.map { $0.updatedAt >= item.updatedAt } == true, "the update did not move updatedAt")
        try expect(store.items().contains { $0.id == other.id && $0.amount == 200 }, "the update touched another item")
    }

    public static func delete(_ store: PantryStore) throws {
        let first = try store.add(name: "Leinsamen", amount: 300, unit: .gram, bestBefore: nil, note: "")
        let second = try store.add(name: "Sonnenblumenkerne", amount: 500, unit: .gram, bestBefore: nil, note: "")
        try store.delete(id: first.id)
        try expect(store.items() == [second], "the removed item is still there, or more went")
        try store.delete(id: first.id)
        try expect(store.items() == [second], "removing twice changed something")
    }

    public static func refusals(_ store: PantryStore) throws {
        do {
            _ = try store.add(name: "   ", amount: 1, unit: .gram, bestBefore: nil, note: "")
            throw ContractViolation(description: "adding an item without a name did not fail")
        } catch PantryStoreError.emptyName {}
        do {
            try store.update(StoredPantryItem(id: "none", name: "Hefe", amount: 1, unit: .piece))
            throw ContractViolation(description: "updating an unknown item did not fail")
        } catch PantryStoreError.unknownItem {}
        let item = try store.add(name: "Hefe", amount: 1, unit: .piece, bestBefore: nil, note: "")
        do {
            var blank = item
            blank.name = ""
            try store.update(blank)
            throw ContractViolation(description: "renaming an item to nothing did not fail")
        } catch PantryStoreError.emptyName {}
        try store.delete(id: "none")
        try expect(store.items() == [item], "an unknown key removed an item, or a refused update changed it")
    }

    public static func matching(_ store: PantryStore) throws {
        let flour = try store.add(name: "Weizenmehl 550", amount: 1_000, unit: .gram, bestBefore: nil, note: "")
        try expect(store.item(matching: "weizenmehl 550 (zimmerwarm)")?.id == flour.id,
                   "the item is not found by the ingredient's name")
        try expect(store.item(matching: "Weizenmehl 1050") == nil, "another flour matched")
        try expect(store.item(matching: "  ") == nil, "an empty name matched")
    }

    // MARK: Helpers

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw ContractViolation(description: message()) }
    }

    /// A day in November 2026 plus `days`, at noon.
    private static func day(_ days: Int) -> Date {
        Date(timeIntervalSince1970: 1_793_534_400 + Double(days) * 86_400)
    }

    public static func receiving(_ store: PantryStore) throws {
        let flour = try store.add(name: "Weizenmehl 550", amount: 1, unit: .kilogram, bestBefore: nil, note: "")
        let joined = try store.receive(name: "weizenmehl 550", amount: 500, unit: .gram)
        try expect(joined.id == flour.id && joined.unit == .kilogram && abs(joined.amount - 1.5) < 0.0001,
                   "500 g did not join 1 kg as 1.5 kg: \(joined)")
        let grams = try store.add(name: "Sesam", amount: 200, unit: .gram, bestBefore: nil, note: "")
        let more = try store.receive(name: "Sesam", amount: 1, unit: .kilogram)
        try expect(more.id == grams.id && more.unit == .gram && abs(more.amount - 1_200) < 0.0001,
                   "1 kg did not join 200 g as 1200 g: \(more)")
        let yeast = try store.add(name: "Hefe", amount: 42, unit: .gram, bestBefore: nil, note: "")
        let cubes = try store.receive(name: "Hefe", amount: 2, unit: .piece)
        try expect(cubes.id != yeast.id && cubes.unit == .piece && cubes.amount == 2,
                   "pieces were booked onto a weighed item: \(cubes)")
        let new = try store.receive(name: "Dinkelmehl 630", amount: 1, unit: .kilogram)
        try expect(new.name == "Dinkelmehl 630" && new.amount == 1 && new.unit == .kilogram, "a new item was not created")
        let count = try store.items().count
        try expect(count == 5, "expected five items, got \(count)")
    }
}
