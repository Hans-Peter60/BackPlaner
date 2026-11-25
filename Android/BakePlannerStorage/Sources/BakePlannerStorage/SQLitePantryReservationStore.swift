//
//  SQLitePantryReservationStore.swift
//  BakePlannerStorage
//
//  The pantry's ledger kept in SQLite — the Android side of
//  PantryReservationStore. Table pantry_reservation (schema in
//  BakePlannerDatabase). A reservation points at its item by the item's
//  UUID and at its plan by the plan's UUID; neither is a foreign key, as
//  on iOS.
//

import BakePlannerCore
import Foundation
import SkipSQLPlus

public final class SQLitePantryReservationStore: PantryReservationStore {

    private let file: BakePlannerDatabase
    private var database: SQLContext { file.context }
    private let now: () -> Date

    public init(file: BakePlannerDatabase, now: @escaping () -> Date = { Date() }) {
        self.file = file
        self.now = now
    }

    // MARK: PantryReservationStore

    public func reservations() throws -> [StoredPantryReservation] {
        try database.selectAll(sql: """
            SELECT id, plan_id, recipe_name, item_id, amount, unit, plan_end, created_at FROM pantry_reservation
            ORDER BY created_at, id
            """, parameters: [])
            .compactMap { row in
                guard let planID = UUID(uuidString: row[1].textValue ?? "") else { return nil }
                return StoredPantryReservation(
                    id: String(row[0].longValue ?? 0),
                    planID: planID,
                    recipeName: row[2].textValue ?? "",
                    itemID: row[3].textValue ?? "",
                    amount: row[4].realValue ?? 0,
                    unit: PantryUnit(stored: row[5].textValue),
                    planEnd: Date(timeIntervalSinceReferenceDate: row[6].realValue ?? 0),
                    createdAt: Date(timeIntervalSinceReferenceDate: row[7].realValue ?? 0))
            }
    }

    public func add(planID: UUID, recipeName: String, itemID: String, amount: Double, unit: PantryUnit,
                    planEnd: Date) throws -> StoredPantryReservation {
        let createdAt = now()
        try database.exec(sql: """
            INSERT INTO pantry_reservation (plan_id, recipe_name, item_id, amount, unit, plan_end, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, parameters: [
                .text(planID.uuidString),
                .text(recipeName),
                .text(itemID),
                .real(max(0, amount)),
                .text(unit.rawValue),
                .real(planEnd.timeIntervalSinceReferenceDate),
                .real(createdAt.timeIntervalSinceReferenceDate),
            ])
        return StoredPantryReservation(id: String(database.lastInsertRowID), planID: planID, recipeName: recipeName,
                                       itemID: itemID, amount: max(0, amount), unit: unit, planEnd: planEnd,
                                       createdAt: createdAt)
    }

    public func delete(planID: UUID) throws {
        try database.exec(sql: "DELETE FROM pantry_reservation WHERE plan_id = ?", parameters: [.text(planID.uuidString)])
    }

    public func delete(id: String) throws {
        guard let rowID = Int64(id) else { return }
        try database.exec(sql: "DELETE FROM pantry_reservation WHERE id = ?", parameters: [.long(rowID)])
    }
}
