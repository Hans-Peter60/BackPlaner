//
//  SQLitePantryStore.swift
//  BakePlannerStorage
//
//  The pantry kept in SQLite — the Android side of PantryStore. Table
//  pantry_item (schema in BakePlannerDatabase), in the same file as the
//  recipes. The store key is the row id; the UUID column is the item's
//  identity the reservations refer to.
//

import BakePlannerCore
import Foundation
import SkipSQLPlus

public final class SQLitePantryStore: PantryStore {

    private let file: BakePlannerDatabase
    private var database: SQLContext { file.context }
    private let now: () -> Date

    /// The store in an open database file — the one the recipes are kept
    /// in (`SQLiteRecipeStore.file`).
    public init(file: BakePlannerDatabase, now: @escaping () -> Date = { Date() }) {
        self.file = file
        self.now = now
    }

    // MARK: PantryStore

    public func items() throws -> [StoredPantryItem] {
        try database.selectAll(sql: """
            SELECT id, uuid, name, amount, unit, best_before, note, updated_at FROM pantry_item
            """, parameters: [])
            .map { row in
                StoredPantryItem(
                    id: String(row[0].longValue ?? 0),
                    name: row[2].textValue ?? "",
                    amount: row[3].realValue ?? 0,
                    unit: PantryUnit(stored: row[4].textValue),
                    bestBefore: row[5].realValue.map { Date(timeIntervalSinceReferenceDate: $0) },
                    note: row[6].textValue ?? "",
                    updatedAt: Date(timeIntervalSinceReferenceDate: row[7].realValue ?? 0),
                    uuid: row[1].textValue)
            }
            // By name as a person reads it (numbers in order, case aside),
            // the way the in-memory store and iOS sort.
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending || ($0.name == $1.name && $0.id < $1.id)
            }
    }

    public func add(name: String, amount: Double, unit: PantryUnit, bestBefore: Date?, note: String) throws -> StoredPantryItem {
        let item = StoredPantryItem(id: "", name: name, amount: amount, unit: unit, bestBefore: bestBefore,
                                    note: note, updatedAt: now(), uuid: UUID().uuidString).normalized
        guard !item.name.isEmpty else { throw PantryStoreError.emptyName }
        try database.exec(sql: """
            INSERT INTO pantry_item (uuid, name, amount, unit, best_before, note, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, parameters: [
                .text(item.uuid),
                .text(item.name),
                .real(item.amount),
                .text(item.unit.rawValue),
                // Seconds since 2001, the way Date keeps them.
                item.bestBefore.map { SQLValue.real($0.timeIntervalSinceReferenceDate) } ?? SQLValue.null,
                item.note.isEmpty ? SQLValue.null : SQLValue.text(item.note),
                .real(item.updatedAt.timeIntervalSinceReferenceDate),
            ])
        var stored = item
        stored.id = String(database.lastInsertRowID)
        return stored
    }

    public func update(_ item: StoredPantryItem) throws {
        guard let rowID = Int64(item.id),
              !(try database.selectAll(sql: "SELECT 1 FROM pantry_item WHERE id = ?",
                                       parameters: [.long(rowID)]).isEmpty) else {
            throw PantryStoreError.unknownItem(item.id)
        }
        let normalized = item.normalized
        guard !normalized.name.isEmpty else { throw PantryStoreError.emptyName }
        try database.exec(sql: """
            UPDATE pantry_item SET name = ?, amount = ?, unit = ?, best_before = ?, note = ?, updated_at = ? WHERE id = ?
            """, parameters: [
                .text(normalized.name),
                .real(normalized.amount),
                .text(normalized.unit.rawValue),
                normalized.bestBefore.map { SQLValue.real($0.timeIntervalSinceReferenceDate) } ?? SQLValue.null,
                normalized.note.isEmpty ? SQLValue.null : SQLValue.text(normalized.note),
                .real(now().timeIntervalSinceReferenceDate),
                .long(rowID),
            ])
    }

    public func delete(id: String) throws {
        guard let rowID = Int64(id) else { return }
        try database.exec(sql: "DELETE FROM pantry_item WHERE id = ?", parameters: [.long(rowID)])
    }
}
