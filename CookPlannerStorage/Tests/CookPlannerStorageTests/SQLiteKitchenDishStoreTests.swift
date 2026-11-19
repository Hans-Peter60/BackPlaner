//
//  SQLiteKitchenDishStoreTests.swift
//  CookPlannerStorageTests
//
//  The dish store contract, checked against SQLite: the same checks the
//  in-memory store passes in BakePlannerCore. Runs on the Mac (swift test).
//

import BakePlannerCore
import CookPlannerStorage
import Foundation
import Testing

@Suite("Dish store contract: SQLite")
struct SQLiteKitchenDishStoreTests {

    @Test("Every check of the contract", arguments: KitchenDishStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(KitchenDishStoreContract.checks.first { $0.name == name })
        let store = try SQLiteKitchenDishStore(path: nil)
        defer { try? store.close() }
        try check.run(store)
    }

    @Test("Dishes stay in the database file when it is closed and opened again, steps and dependencies in order")
    func persistence() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("dishes-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let first = try SQLiteKitchenDishStore(path: path)
        for dish in KitchenSampleDishes.all { try first.save(dish) }
        let own = KitchenDishStoreContract.sampleDish()
        try first.save(own)
        try first.close()

        let second = try SQLiteKitchenDishStore(path: path)
        defer { try? second.close() }
        #expect(try second.dishes().count == 4)
        for dish in KitchenSampleDishes.all + [own] {
            #expect(try second.dish(id: dish.id) == dish, "\(dish.name)")
        }
    }

    @Test("A failed save leaves the previous dish untouched")
    func atomicSave() throws {
        let store = try SQLiteKitchenDishStore(path: nil)
        defer { try? store.close() }
        let dish = KitchenDishStoreContract.sampleDish()
        try store.save(dish)
        var broken = dish
        broken.name = ""
        #expect(throws: KitchenDishStoreError.incomplete) { try store.save(broken) }
        #expect(try store.dish(id: dish.id) == dish)
    }
}
