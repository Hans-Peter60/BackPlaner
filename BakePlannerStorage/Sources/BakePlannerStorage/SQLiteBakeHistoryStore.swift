//
//  SQLiteBakeHistoryStore.swift
//  BakePlannerStorage
//
//  The bake history kept in SQLite — the Android side of BakeHistoryStore.
//  Tables bake_history and bake_history_image (schema in
//  BakePlannerDatabase), in the same file as the recipes: removing a
//  recipe removes its entries, removing an entry its photos.
//

import BakePlannerCore
import Foundation
import SkipSQLPlus

public final class SQLiteBakeHistoryStore: BakeHistoryStore {

    private let file: BakePlannerDatabase
    private var database: SQLContext { file.context }

    /// The store in an open database file — the one the recipes are kept
    /// in (`SQLiteRecipeStore.file`), so entries can refer to them.
    public init(file: BakePlannerDatabase) {
        self.file = file
    }

    // MARK: BakeHistoryStore

    public func entries(includingImages: Bool) throws -> [StoredBakeHistory] {
        try database.selectAll(sql: "SELECT \(Self.columns) FROM bake_history ORDER BY date DESC, id")
            .map { try entry(from: $0, includingImages: includingImages) }
    }

    public func entries(ofRecipe recipeID: String, includingImages: Bool) throws -> [StoredBakeHistory] {
        guard let rowID = Int64(recipeID) else { return [] }
        return try database.selectAll(sql: """
            SELECT \(Self.columns) FROM bake_history WHERE recipe_id = ? ORDER BY date DESC, id
            """, parameters: [.long(rowID)])
            .map { try entry(from: $0, includingImages: includingImages) }
    }

    public func entry(id: String) throws -> StoredBakeHistory? {
        guard let rowID = Int64(id) else { return nil }
        return try database.selectAll(sql: "SELECT \(Self.columns) FROM bake_history WHERE id = ?",
                                      parameters: [.long(rowID)])
            .first.map { try entry(from: $0, includingImages: true) }
    }

    public func add(toRecipe recipeID: String, date: Date, comment: String, images: [Data],
                    facts: BakeHistoryFacts) throws -> StoredBakeHistory {
        guard let recipeRowID = Int64(recipeID),
              !(try database.selectAll(sql: "SELECT 1 FROM recipe WHERE id = ?",
                                       parameters: [.long(recipeRowID)]).isEmpty) else {
            throw BakeHistoryStoreError.unknownRecipe(recipeID)
        }
        let normalized = facts.normalized
        let rowID: Int64 = try database.transaction {
            try database.exec(sql: """
                INSERT INTO bake_history (recipe_id, date, comment, room_temperature, dough_temperature,
                    bulk_proof_minutes, final_proof_minutes, flour, outcome)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, parameters: [.long(recipeRowID)] + Self.values(date: date, comment: comment, facts: normalized))
            let rowID = database.lastInsertRowID
            try insertImages(images, entry: rowID)
            try database.exec(sql: "UPDATE recipe SET bake_history_flag = 1 WHERE id = ?",
                              parameters: [.long(recipeRowID)])
            return rowID
        }
        return StoredBakeHistory(id: String(rowID), recipeID: recipeID, date: date, comment: comment,
                                 images: images, facts: normalized)
    }

    public func update(_ entry: StoredBakeHistory) throws {
        guard let rowID = Int64(entry.id),
              !(try database.selectAll(sql: "SELECT 1 FROM bake_history WHERE id = ?",
                                       parameters: [.long(rowID)]).isEmpty) else {
            throw BakeHistoryStoreError.unknownEntry(entry.id)
        }
        try database.transaction {
            try database.exec(sql: """
                UPDATE bake_history SET date = ?, comment = ?, room_temperature = ?, dough_temperature = ?,
                    bulk_proof_minutes = ?, final_proof_minutes = ?, flour = ?, outcome = ?
                WHERE id = ?
                """, parameters: Self.values(date: entry.date, comment: entry.comment, facts: entry.facts.normalized)
                    + [.long(rowID)])
            try database.exec(sql: "DELETE FROM bake_history_image WHERE bake_history_id = ?",
                              parameters: [.long(rowID)])
            try insertImages(entry.images, entry: rowID)
        }
    }

    public func delete(id: String) throws {
        guard let rowID = Int64(id) else { return }
        try database.exec(sql: "DELETE FROM bake_history WHERE id = ?", parameters: [.long(rowID)])
    }

    // MARK: Helpers

    private static let columns = """
        id, recipe_id, date, comment, room_temperature, dough_temperature, bulk_proof_minutes,
        final_proof_minutes, flour, outcome
        """

    private func entry(from row: [SQLValue], includingImages: Bool) throws -> StoredBakeHistory {
        let rowID = row[0].longValue ?? 0
        let facts = BakeHistoryFacts(roomTemperature: row[4].realValue,
                                     doughTemperature: row[5].realValue,
                                     bulkProofMinutes: row[6].longValue.map { Int($0) },
                                     finalProofMinutes: row[7].longValue.map { Int($0) },
                                     flour: row[8].textValue ?? "",
                                     outcome: row[9].textValue ?? "")
        return StoredBakeHistory(id: String(rowID),
                                 recipeID: String(row[1].longValue ?? 0),
                                 date: Date(timeIntervalSinceReferenceDate: row[2].realValue ?? 0),
                                 comment: row[3].textValue ?? "",
                                 images: includingImages ? try images(of: rowID) : [],
                                 facts: facts)
    }

    private func images(of rowID: Int64) throws -> [Data] {
        try database.selectAll(sql: """
            SELECT data FROM bake_history_image WHERE bake_history_id = ? ORDER BY position, id
            """, parameters: [.long(rowID)])
            .compactMap { $0[0].blobValue }
    }

    private func insertImages(_ images: [Data], entry rowID: Int64) throws {
        for (position, image) in images.enumerated() {
            try database.exec(sql: "INSERT INTO bake_history_image (bake_history_id, position, data) VALUES (?, ?, ?)",
                              parameters: [.long(rowID), .long(Int64(position)), .blob(image)])
        }
    }

    /// Date, comment and facts in the order of the columns after recipe_id.
    private static func values(date: Date, comment: String, facts: BakeHistoryFacts) -> [SQLValue] {
        [
            // Seconds since 2001, the way Date keeps them, so a date comes
            // back exactly as it went in.
            .real(date.timeIntervalSinceReferenceDate),
            .text(comment),
            facts.roomTemperature.map { SQLValue.real($0) } ?? SQLValue.null,
            facts.doughTemperature.map { SQLValue.real($0) } ?? SQLValue.null,
            facts.bulkProofMinutes.map { SQLValue.long(Int64($0)) } ?? SQLValue.null,
            facts.finalProofMinutes.map { SQLValue.long(Int64($0)) } ?? SQLValue.null,
            facts.flour.isEmpty ? SQLValue.null : SQLValue.text(facts.flour),
            facts.outcome.isEmpty ? SQLValue.null : SQLValue.text(facts.outcome),
        ]
    }
}
