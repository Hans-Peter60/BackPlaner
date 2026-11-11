//
//  CoreDataPantryStoreTests.swift
//  BackPlanerTests
//
//  The pantry contract, checked against Core Data in memory: the same
//  checks the in-memory store passes in the package.
//

import BakePlannerCore
import CoreData
import Foundation
import Testing
@testable import BackPlaner

@Suite("Pantry contract: Core Data")
@MainActor
struct CoreDataPantryStoreTests {

    private func newStore() -> CoreDataPantryStore {
        CoreDataPantryStore(context: PersistenceController(inMemory: true).container.viewContext)
    }

    @Test("Every check of the contract", arguments: PantryStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(PantryStoreContract.checks.first { $0.name == name })
        try check.run(newStore())
    }

    @Test("A bought line joins the item of the same name and unit; another unit makes a new item")
    func receive() throws {
        let store = newStore()
        _ = try store.add(name: "Weizenmehl 550", amount: 500, unit: .gram, bestBefore: nil, note: "")
        let joined = try store.receive(name: "weizenmehl 550 (zimmerwarm)", amount: 1_000, unit: .gram)
        #expect(joined.amount == 1_500)
        let separate = try store.receive(name: "Weizenmehl 550", amount: 1, unit: .kilogram)
        #expect(separate.id != joined.id && separate.unit == .kilogram)
        #expect(try store.items().count == 2)
    }

    @Test("The shopping list shrinks a kilogram line in kilograms and leaves a spoon whole (needs the unit tables)")
    func reduceWithUnits() {
        let kilo = [ShoppingListEntry(name: "Dinkelmehl 630", unit: "kg", weight: 1.5, num: 0, denom: 0)]
        let flour = StoredPantryItem(id: "d", name: "Dinkelmehl 630", amount: 400, unit: .gram)
        #expect(PantryMatcher.reduce(kilo, pantry: [flour]).first?.weight == 1.1)
        let spoon = [ShoppingListEntry(name: "Honig", unit: "EL", weight: 2, num: 0, denom: 0)]
        let honey = StoredPantryItem(id: "h", name: "Honig", amount: 5, unit: .gram)
        #expect(PantryMatcher.reduce(spoon, pantry: [honey]).first?.weight == 2)
        // Enough honey in the house: the spoon goes.
        let jar = StoredPantryItem(id: "j", name: "Honig", amount: 500, unit: .gram)
        #expect(PantryMatcher.reduce(spoon, pantry: [jar]).isEmpty)
    }

    @Test("What a shopping-list line puts in: kilograms and pieces as written, the rest in grams")
    func intake() {
        #expect(Pantry.intake(unit: "kg", weight: 2.5, normWeight: 2_500, num: 0, denom: 0) == (2.5, .kilogram))
        #expect(Pantry.intake(unit: "St", weight: 0, normWeight: 0, num: 1, denom: 2) == (1, .piece))
        #expect(Pantry.intake(unit: "St", weight: 6, normWeight: 6, num: 0, denom: 0) == (6, .piece))
        #expect(Pantry.intake(unit: "EL", weight: 2, normWeight: 30, num: 0, denom: 0) == (30, .gram))
        #expect(Pantry.intake(unit: "g", weight: 450, normWeight: 450, num: 0, denom: 0) == (450, .gram))
    }
}
