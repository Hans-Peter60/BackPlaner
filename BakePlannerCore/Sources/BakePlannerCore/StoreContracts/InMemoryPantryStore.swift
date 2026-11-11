//
//  InMemoryPantryStore.swift
//  BakePlannerCore
//
//  A PantryStore that keeps everything in memory: the reference the
//  contract is checked against first, and a stand-in for tests.
//

import Foundation

public final class InMemoryPantryStore: PantryStore {

    private var stored: [String: StoredPantryItem] = [:]
    private var nextID = 1
    private let now: () -> Date

    public init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    public func items() throws -> [StoredPantryItem] {
        stored.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending || ($0.name == $1.name && $0.id < $1.id)
        }
    }

    public func add(name: String, amount: Double, unit: PantryUnit, bestBefore: Date?, note: String) throws -> StoredPantryItem {
        let item = StoredPantryItem(id: "memory-pantry-\(nextID)", name: name, amount: amount, unit: unit,
                                    bestBefore: bestBefore, note: note, updatedAt: now()).normalized
        guard !item.name.isEmpty else { throw PantryStoreError.emptyName }
        nextID += 1
        stored[item.id] = item
        return item
    }

    public func update(_ item: StoredPantryItem) throws {
        guard stored[item.id] != nil else { throw PantryStoreError.unknownItem(item.id) }
        var normalized = item.normalized
        guard !normalized.name.isEmpty else { throw PantryStoreError.emptyName }
        normalized.updatedAt = now()
        stored[item.id] = normalized
    }

    public func delete(id: String) throws {
        stored[id] = nil
    }
}
