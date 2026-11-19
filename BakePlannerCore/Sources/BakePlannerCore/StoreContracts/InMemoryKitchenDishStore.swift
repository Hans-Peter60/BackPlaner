//
//  InMemoryKitchenDishStore.swift
//  BakePlannerCore
//
//  The dish store without a database, for tests and previews.
//

import Foundation

public final class InMemoryKitchenDishStore: KitchenDishStore {

    private var storage = [String: KitchenDish]()

    public init(dishes: [KitchenDish] = []) {
        for dish in dishes { storage[dish.id] = dish }
    }

    public func dishes() throws -> [KitchenDish] {
        storage.values.sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }

    public func dish(id: String) throws -> KitchenDish? {
        storage[id]
    }

    public func save(_ dish: KitchenDish) throws {
        guard !dish.id.isEmpty, !dish.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KitchenDishStoreError.incomplete
        }
        storage[dish.id] = dish
    }

    public func delete(id: String) throws {
        storage[id] = nil
    }
}
