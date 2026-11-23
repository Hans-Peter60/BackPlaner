//
//  CoreDataPantryReservationStore.swift
//  BackPlaner
//
//  The pantry's reservations in Core Data (and iCloud) — the iOS side of
//  PantryReservationStore.
//

import BakePlannerCore
import CoreData
import Foundation

struct CoreDataPantryReservationStore: PantryReservationStore {

    let context: NSManagedObjectContext

    func reservations() throws -> [StoredPantryReservation] {
        try context.fetch(PantryReservation.fetchRequest())
            .compactMap(Self.stored)
            .sorted { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id < $1.id }
    }

    func add(planID: UUID, recipeName: String, itemID: String, amount: Double, unit: PantryUnit, planEnd: Date) throws -> StoredPantryReservation {
        let reservation = PantryReservation(context: context)
        reservation.id = UUID()
        reservation.planID = planID
        reservation.recipeName = recipeName
        reservation.itemID = UUID(uuidString: itemID)
        reservation.amount = max(0, amount)
        reservation.unit = unit.rawValue
        reservation.planEnd = planEnd
        reservation.createdAt = Date()
        try save()
        return Self.stored(reservation) ?? StoredPantryReservation(id: reservation.storeKey, planID: planID, recipeName: recipeName,
                                                                  itemID: itemID, amount: amount, unit: unit, planEnd: planEnd)
    }

    func delete(planID: UUID) throws {
        let request = PantryReservation.fetchRequest()
        request.predicate = NSPredicate(format: "planID == %@", planID as CVarArg)
        for reservation in try context.fetch(request) {
            context.delete(reservation)
        }
        try save()
    }

    func delete(id: String) throws {
        guard let reservation: PantryReservation = context.existingObject(storeKey: id) else { return }
        context.delete(reservation)
        try save()
    }

    static func stored(_ reservation: PantryReservation) -> StoredPantryReservation? {
        guard let planID = reservation.planID, let itemID = reservation.itemID else { return nil }
        return StoredPantryReservation(id: reservation.storeKey,
                                       planID: planID,
                                       recipeName: reservation.recipeName ?? "",
                                       itemID: itemID.uuidString,
                                       amount: reservation.amount,
                                       unit: PantryUnit(stored: reservation.unit),
                                       planEnd: reservation.planEnd ?? .distantPast,
                                       createdAt: reservation.createdAt ?? .distantPast)
    }

    private func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}
