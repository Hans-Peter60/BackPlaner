//
//  CoreDataPantryReservationStoreTests.swift
//  BackPlanerTests
//
//  The pantry reservation contract against Core Data in memory, and the
//  ledger service's bookings: reserve on planning, release on deletion,
//  convert when the plan has ended, undo.
//

import BakePlannerCore
import CoreData
import Foundation
import Testing
@testable import BackPlaner

@Suite("Pantry reservations: Core Data and the ledger service")
@MainActor
struct CoreDataPantryReservationStoreTests {

    private func newContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    @Test("Every check of the contract", arguments: PantryReservationStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(PantryReservationStoreContract.checks.first { $0.name == name })
        try check.run(CoreDataPantryReservationStore(context: newContext()))
    }

    private func bread() -> RecipeExportData {
        RecipeExportData(name: "Roggenbrot", summary: "", prepTime: 300, totalWeight: 1_000, tags: [], rating: 0, recurrenceIntervalDays: 0,
                         components: [RecipeExportComponent(name: "Teig", number: 1, ingredients: [
                            RecipeExportIngredient(name: "Roggenmehl 1150", number: 1, unit: "g", weight: 500, normWeight: 500, num: 0, denom: 0),
                            RecipeExportIngredient(name: "Wasser", number: 2, unit: "g", weight: 400, normWeight: 400, num: 0, denom: 0),
                         ])], instructions: [])
    }

    @Test("Planning reserves against the available stock, deleting the plan releases, the plan's end converts, undo books back")
    func ledgerRoundTrip() throws {
        let context = newContext()
        let items = CoreDataPantryStore(context: context)
        let reservations = CoreDataPantryReservationStore(context: context)
        let flour = try items.add(name: "Roggenmehl 1150", amount: 1, unit: .kilogram, bestBefore: nil, note: "")
        let end = Date().addingTimeInterval(3_600)

        let first = UUID(), second = UUID()
        PantryLedgerService.reserve(recipe: bread(), planID: first, scale: 1, planEnd: end, in: context)
        PantryLedgerService.reserve(recipe: bread(), planID: second, scale: 1, planEnd: end, in: context)
        var stored = try reservations.reservations()
        #expect(stored.count == 2)
        // Reserved in the item's unit: half a kilogram each.
        #expect(stored.allSatisfy { $0.itemID == flour.uuid && $0.amount == 0.5 && $0.unit == .kilogram })
        // Stock untouched, nothing available any more.
        #expect(try items.items().first?.amount == 1)
        #expect(PantryLedger.available(try items.items(), reservations: stored).first?.amount == 0)

        // The second plan is deleted: its reservation goes, the first stays.
        PantryLedgerService.release(planIDs: [second], in: context)
        stored = try reservations.reservations()
        #expect(stored.map(\.planID) == [first])

        // Reserving again under the first id replaces, never doubles.
        PantryLedgerService.reserve(recipe: bread(), planID: first, scale: 1, planEnd: end, in: context)
        #expect(try reservations.reservations().count == 1)

        // Before the end nothing converts; after it the stock drops and a booking is noted.
        PantryLedgerService.reconcile(in: context, now: Date())
        #expect(try items.items().first?.amount == 1)
        PantryLedgerService.reconcile(in: context, now: end.addingTimeInterval(60))
        #expect(try items.items().first?.amount == 0.5)
        #expect(try reservations.reservations().isEmpty)

        // The booking list on this device, and undo.
        let bookings = PantryBookings.all()
        let booking = try #require(bookings.first { $0.itemID == flour.uuid && $0.recipeName == "Roggenbrot" })
        PantryLedgerService.undo(booking, in: context)
        #expect(try items.items().first?.amount == 1)
        #expect(!PantryBookings.all().contains { $0.id == booking.id })
    }

    @Test("Releasing by recipe name takes every plan of that recipe")
    func releaseByName() throws {
        let context = newContext()
        let items = CoreDataPantryStore(context: context)
        _ = try items.add(name: "Roggenmehl 1150", amount: 2, unit: .kilogram, bestBefore: nil, note: "")
        PantryLedgerService.reserve(recipe: bread(), planID: UUID(), scale: 1, planEnd: .distantFuture, in: context)
        PantryLedgerService.reserve(recipe: bread(), planID: UUID(), scale: 1, planEnd: .distantFuture, in: context)
        #expect(try CoreDataPantryReservationStore(context: context).reservations().count == 2)
        PantryLedgerService.release(recipeName: "Roggenbrot", in: context)
        #expect(try CoreDataPantryReservationStore(context: context).reservations().isEmpty)
    }
}
