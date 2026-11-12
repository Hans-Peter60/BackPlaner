//
//  InMemoryPantryReservationStore.swift
//  BakePlannerCore
//

import Foundation

public final class InMemoryPantryReservationStore: PantryReservationStore {
    private var stored: [String: StoredPantryReservation] = [:]
    private var nextID = 1

    public init() {}

    public func reservations() throws -> [StoredPantryReservation] {
        stored.values.sorted { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id < $1.id }
    }

    public func add(planID: UUID, recipeName: String, itemID: String, amount: Double, unit: PantryUnit, planEnd: Date) throws -> StoredPantryReservation {
        let reservation = StoredPantryReservation(id: "memory-reservation-\(nextID)", planID: planID, recipeName: recipeName,
                                                  itemID: itemID, amount: max(0, amount), unit: unit, planEnd: planEnd)
        nextID += 1
        stored[reservation.id] = reservation
        return reservation
    }

    public func delete(planID: UUID) throws {
        stored = stored.filter { $0.value.planID != planID }
    }

    public func delete(id: String) throws {
        stored[id] = nil
    }
}
