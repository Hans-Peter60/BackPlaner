import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Pantry reservations contract: in memory")
struct InMemoryPantryReservationStoreTests {
    @Test("Every check of the contract", arguments: PantryReservationStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(PantryReservationStoreContract.checks.first { $0.name == name })
        try check.run(InMemoryPantryReservationStore())
    }
}

@Suite("Pantry ledger: available, shortfalls over several breads, conversion")
struct PantryLedgerTests {

    private func item(_ uuid: String, _ name: String, _ amount: Double, _ unit: PantryUnit) -> StoredPantryItem {
        StoredPantryItem(id: "key-\(uuid)", name: name, amount: amount, unit: unit, uuid: uuid)
    }

    private func reservation(_ itemID: String, _ amount: Double, _ unit: PantryUnit, plan: UUID = UUID(), end: Date = .distantFuture) -> StoredPantryReservation {
        StoredPantryReservation(id: UUID().uuidString, planID: plan, recipeName: "R", itemID: itemID, amount: amount, unit: unit, planEnd: end)
    }

    private func ingredient(_ name: String, _ weight: Double, _ unit: String = "g") -> RecipeExportIngredient {
        RecipeExportIngredient(name: name, number: 1, unit: unit, weight: weight, normWeight: weight, num: 0, denom: 0)
    }

    private func recipe(_ ingredients: [RecipeExportIngredient]) -> RecipeExportData {
        RecipeExportData(name: "R", summary: "", prepTime: 0, totalWeight: 1_000, tags: [], rating: 0, recurrenceIntervalDays: 0,
                         components: [RecipeExportComponent(name: "Teig", number: 1, ingredients: ingredients)], instructions: [])
    }

    @Test("Available is stock less reservations, in the item's unit, never below nothing")
    func available() {
        let flour = item("f", "Roggenmehl 1150", 1, .kilogram)
        let eggs = item("e", "Ei", 6, .piece)
        let reservations = [reservation("f", 250, .gram), reservation("f", 0.25, .kilogram), reservation("e", 8, .piece)]
        let free = PantryLedger.available([flour, eggs], reservations: reservations)
        #expect(free[0].amount == 0.5 && free[0].unit == .kilogram)
        #expect(free[1].amount == 0)
        #expect(PantryLedger.reservedAmount(of: flour, reservations: reservations) == 0.5)
        #expect(PantryLedger.reservedAmount(of: eggs, reservations: reservations) == 8)
    }

    @Test("Shortfalls add the breads up: two breads at 500 g each against 750 g leave 250 g missing")
    func shortfalls() {
        let pantry = [item("f", "Roggenmehl 1150", 750, .gram), item("w", "Weizenmehl 550", 2, .kilogram)]
        let rye = recipe([ingredient("Roggenmehl 1150", 500), ingredient("Wasser", 350), ingredient("Salz", 10)])
        let mixed = recipe([ingredient("Roggenmehl 1150", 500), ingredient("Weizenmehl 550", 300), ingredient("Hefe", 5)])
        let missing = PantryLedger.shortfalls(for: [(rye, 1), (mixed, 1)], available: pantry)
        #expect(missing.map(\.name) == ["Roggenmehl 1150", "Hefe"])
        #expect(missing[0].missingBase == 250 && missing[1].missingBase == 5)
        // Half the second bread: the rye fits.
        #expect(PantryLedger.shortfalls(for: [(rye, 1), (mixed, 0.5)], available: pantry).map(\.name) == ["Hefe"])
        // Nothing missing: empty.
        #expect(PantryLedger.shortfalls(for: [(rye, 1)], available: pantry).isEmpty)
    }

    @Test("Due reservations are those whose plan has ended; converting takes the stock down")
    func conversion() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let due = reservation("f", 300, .gram, end: now.addingTimeInterval(-60))
        let open = reservation("f", 200, .gram, end: now.addingTimeInterval(3_600))
        #expect(PantryLedger.dueForConversion([due, open], now: now) == [due])
        let flour = item("f", "Roggenmehl 1150", 1, .kilogram)
        #expect(PantryLedger.converted(flour, by: due).amount == 0.7)
        let little = item("f", "Roggenmehl 1150", 100, .gram)
        #expect(PantryLedger.converted(little, by: due).amount == 0)
    }

    @Test("A booking survives JSON for the undo list")
    func bookingCodable() throws {
        let booking = PantryBooking(date: Date(timeIntervalSince1970: 1_800_000_000), recipeName: "Landbrot", itemID: "f",
                                    itemName: "Roggenmehl 1150", amount: 0.3, unit: .kilogram)
        let data = try JSONEncoder().encode([booking])
        #expect(try JSONDecoder().decode([PantryBooking].self, from: data) == [booking])
    }
}
