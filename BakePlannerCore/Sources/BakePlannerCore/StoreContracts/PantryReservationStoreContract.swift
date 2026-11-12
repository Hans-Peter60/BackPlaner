//
//  PantryReservationStoreContract.swift
//  BakePlannerCore
//
//  What every PantryReservationStore must do: in memory, Core Data, SQLite.
//

import Foundation

public enum PantryReservationStoreContract {

    public typealias Check = (PantryReservationStore) throws -> Void

    public static let checks: [(name: String, run: Check)] = [
        ("an empty store has nothing", emptyStore),
        ("a reservation comes back as it was added", addAndRead),
        ("a plan's reservations go together, the other plan's stay", deleteByPlan),
        ("one reservation goes on its own; unknown keys change nothing", deleteOne),
    ]

    /// Item ids are UUID strings, as the pantry items carry them.
    static let itemA = "0A3F0E5C-6C1B-4B0E-9D7E-1F2A3B4C5D6E"
    static let itemB = "7B8C9D0E-1F2A-4B3C-8D4E-5F6A7B8C9D0E"

    public static func emptyStore(_ store: PantryReservationStore) throws {
        try expect(store.reservations().isEmpty, "an empty store has reservations")
    }

    public static func addAndRead(_ store: PantryReservationStore) throws {
        let plan = UUID()
        let added = try store.add(planID: plan, recipeName: "Landbrot", itemID: itemA, amount: 0.5, unit: .kilogram, planEnd: moment(12))
        try expect(!added.id.isEmpty, "the new reservation has no key")
        try expect(added.planID == plan && added.recipeName == "Landbrot" && added.itemID == itemA
                   && added.amount == 0.5 && added.unit == .kilogram && added.planEnd == moment(12),
                   "add returns other content than it was given: \(added)")
        try expect(added.baseAmount == 500, "0.5 kg are not 500 g")
        try expect(store.reservations() == [added], "the store's reservations differ from the one added")
    }

    public static func deleteByPlan(_ store: PantryReservationStore) throws {
        let first = UUID(), second = UUID()
        _ = try store.add(planID: first, recipeName: "A", itemID: itemA, amount: 100, unit: .gram, planEnd: moment(10))
        _ = try store.add(planID: first, recipeName: "A", itemID: itemB, amount: 2, unit: .piece, planEnd: moment(10))
        let kept = try store.add(planID: second, recipeName: "B", itemID: itemA, amount: 200, unit: .gram, planEnd: moment(11))
        try store.delete(planID: first)
        try expect(store.reservations() == [kept], "the plan's reservations did not go together, or the other plan's went")
        try store.delete(planID: first)
        try expect(store.reservations() == [kept], "deleting a gone plan changed something")
    }

    public static func deleteOne(_ store: PantryReservationStore) throws {
        let plan = UUID()
        let first = try store.add(planID: plan, recipeName: "A", itemID: itemA, amount: 100, unit: .gram, planEnd: moment(10))
        let second = try store.add(planID: plan, recipeName: "A", itemID: itemB, amount: 50, unit: .gram, planEnd: moment(10))
        try store.delete(id: first.id)
        try expect(store.reservations() == [second], "the reservation did not go, or the other went")
        try store.delete(id: "none")
        try expect(store.reservations() == [second], "an unknown key removed a reservation")
    }

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw ContractViolation(description: message()) }
    }

    private static func moment(_ hour: Int) -> Date {
        Date(timeIntervalSince1970: 1_793_520_000 + Double(hour) * 3_600)
    }
}
