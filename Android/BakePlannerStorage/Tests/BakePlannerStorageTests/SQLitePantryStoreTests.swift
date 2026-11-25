//
//  SQLitePantryStoreTests.swift
//  BakePlannerStorageTests
//
//  The pantry contract and the ledger contract, checked against SQLite:
//  the same checks the in-memory stores pass in BakePlannerCore and the
//  Core Data stores in the iOS app.
//

import BakePlannerCore
import BakePlannerStorage
import Foundation
import Testing

@Suite("Pantry contract: SQLite")
struct SQLitePantryStoreTests {

    @Test("Every check of the contract", arguments: PantryStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(PantryStoreContract.checks.first { $0.name == name })
        let recipes = try SQLiteRecipeStore(path: nil)
        defer { try? recipes.close() }
        try check.run(SQLitePantryStore(file: recipes.file))
    }

    @Test("Items stay in the database file, with their UUID, when it is closed and opened again")
    func persistence() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("pantry-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let first = try SQLiteRecipeStore(path: path)
        let store = SQLitePantryStore(file: first.file, now: { Date(timeIntervalSinceReferenceDate: 815_000_000) })
        let flour = try store.add(name: "Weizenmehl 550", amount: 1, unit: .kilogram,
                                  bestBefore: Date(timeIntervalSinceReferenceDate: 820_000_000), note: "angebrochen")
        let yeast = try store.add(name: "Hefe", amount: 2, unit: .piece, bestBefore: nil, note: "")
        try first.close()

        let second = try SQLiteRecipeStore(path: path)
        defer { try? second.close() }
        let items = try SQLitePantryStore(file: second.file).items()
        #expect(items == [yeast, flour])
        #expect(items.first?.uuid == yeast.uuid)
        #expect(UUID(uuidString: flour.uuid) != nil)
        #expect(flour.uuid != flour.id)
    }
}

@Suite("Pantry ledger contract: SQLite")
struct SQLitePantryReservationStoreTests {

    @Test("Every check of the contract", arguments: PantryReservationStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(PantryReservationStoreContract.checks.first { $0.name == name })
        let recipes = try SQLiteRecipeStore(path: nil)
        defer { try? recipes.close() }
        try check.run(SQLitePantryReservationStore(file: recipes.file))
    }

    @Test("Reservations stay in the database file when it is closed and opened again")
    func persistence() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("reservations-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let first = try SQLiteRecipeStore(path: path)
        let plan = UUID()
        let store = SQLitePantryReservationStore(file: first.file, now: { Date(timeIntervalSinceReferenceDate: 815_000_000) })
        let reserved = try store.add(planID: plan, recipeName: "Landbrot", itemID: UUID().uuidString, amount: 0.5,
                                     unit: .kilogram, planEnd: Date(timeIntervalSinceReferenceDate: 815_100_000))
        try first.close()

        let second = try SQLiteRecipeStore(path: path)
        defer { try? second.close() }
        #expect(try SQLitePantryReservationStore(file: second.file).reservations() == [reserved])
    }
}
