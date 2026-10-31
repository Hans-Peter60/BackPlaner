//
//  SQLiteStarterFeedingLogStore.swift
//  BakePlannerStorage
//
//  The starter feeding diary kept in SQLite — the Android side of
//  StarterFeedingLogStore. Table starter_feeding (schema in
//  BakePlannerDatabase), in the same file as the recipes: removing a recipe
//  removes its feedings.
//

import BakePlannerCore
import Foundation
import SkipSQLPlus

public final class SQLiteStarterFeedingLogStore: StarterFeedingLogStore {

    private let file: BakePlannerDatabase
    private var database: SQLContext { file.context }

    /// The store in an open database file — the one the recipes are kept
    /// in (`SQLiteRecipeStore.file`), so feedings can refer to them.
    public init(file: BakePlannerDatabase) {
        self.file = file
    }

    // MARK: StarterFeedingLogStore

    public func feedings(ofRecipe recipeID: String) throws -> [StoredStarterFeeding] {
        guard let recipeRowID = Int64(recipeID) else { return [] }
        return try database.selectAll(sql: """
            SELECT id, date, peak_minutes, float_test_passed, note FROM starter_feeding
            WHERE recipe_id = ? ORDER BY date DESC, id
            """, parameters: [.long(recipeRowID)])
            .map { row in
                StoredStarterFeeding(
                    id: String(row[0].longValue ?? 0),
                    recipeID: recipeID,
                    date: Date(timeIntervalSinceReferenceDate: row[1].realValue ?? 0),
                    facts: StarterFeedingFacts(peakMinutes: row[2].longValue.map { Int($0) },
                                               floatTestPassed: row[3].longValue.map { $0 != 0 },
                                               note: row[4].textValue ?? ""))
            }
    }

    public func add(toRecipe recipeID: String, date: Date, facts: StarterFeedingFacts) throws -> StoredStarterFeeding {
        guard let recipeRowID = Int64(recipeID),
              !(try database.selectAll(sql: "SELECT 1 FROM recipe WHERE id = ?",
                                       parameters: [.long(recipeRowID)]).isEmpty) else {
            throw StarterFeedingLogStoreError.unknownRecipe(recipeID)
        }
        let normalized = facts.normalized
        try database.exec(sql: """
            INSERT INTO starter_feeding (recipe_id, date, peak_minutes, float_test_passed, note)
            VALUES (?, ?, ?, ?, ?)
            """, parameters: [
                .long(recipeRowID),
                // Seconds since 2001, the way Date keeps them, so a date
                // comes back exactly as it went in.
                .real(date.timeIntervalSinceReferenceDate),
                normalized.peakMinutes.map { SQLValue.long(Int64($0)) } ?? SQLValue.null,
                normalized.floatTestPassed.map { SQLValue.long($0 ? 1 : 0) } ?? SQLValue.null,
                normalized.note.isEmpty ? SQLValue.null : SQLValue.text(normalized.note),
            ])
        return StoredStarterFeeding(id: String(database.lastInsertRowID), recipeID: recipeID, date: date,
                                    facts: normalized)
    }

    public func update(_ feeding: StoredStarterFeeding) throws {
        guard let rowID = Int64(feeding.id),
              !(try database.selectAll(sql: "SELECT 1 FROM starter_feeding WHERE id = ?",
                                       parameters: [.long(rowID)]).isEmpty) else {
            throw StarterFeedingLogStoreError.unknownFeeding(feeding.id)
        }
        let facts = feeding.facts.normalized
        try database.exec(sql: """
            UPDATE starter_feeding SET peak_minutes = ?, float_test_passed = ?, note = ? WHERE id = ?
            """, parameters: [
                facts.peakMinutes.map { SQLValue.long(Int64($0)) } ?? SQLValue.null,
                facts.floatTestPassed.map { SQLValue.long($0 ? 1 : 0) } ?? SQLValue.null,
                facts.note.isEmpty ? SQLValue.null : SQLValue.text(facts.note),
                .long(rowID),
            ])
    }

    public func delete(id: String) throws {
        guard let rowID = Int64(id) else { return }
        try database.exec(sql: "DELETE FROM starter_feeding WHERE id = ?", parameters: [.long(rowID)])
    }
}
