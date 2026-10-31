//
//  SQLiteScheduledStepStore.swift
//  BakePlannerStorage
//
//  The scheduled steps of all plans kept in SQLite — the Android side of
//  ScheduledStepStore. Table scheduled_step (schema in BakePlannerDatabase),
//  in the same file as the recipes. Like the Core Data store, it answers
//  without throwing: a step that cannot be read or written is left out, as
//  planning has nobody to show such an error to.
//

import BakePlannerCore
import Foundation
import SkipSQLPlus

public final class SQLiteScheduledStepStore: ScheduledStepStore {

    private let file: BakePlannerDatabase
    private var database: SQLContext { file.context }

    /// The store in an open database file — the one the recipes are kept in
    /// (`SQLiteRecipeStore.file`).
    public init(file: BakePlannerDatabase) {
        self.file = file
    }

    // MARK: ScheduledStepStore

    public func steps(excludingRecipe recipeName: String) -> [ScheduledStepData] {
        select(where: "recipe_name <> ?", [.text(recipeName)]).map(\.data)
    }

    public func hasSteps(recipeName: String) -> Bool {
        exists(where: "recipe_name = ?", [.text(recipeName)])
    }

    public func hasSteps(recipeName: String, onOrAfter date: Date) -> Bool {
        exists(where: "recipe_name = ? AND date >= ?", [.text(recipeName), .real(date.timeIntervalSinceReferenceDate)])
    }

    public func add(_ steps: [ScheduledStepData]) {
        _ = try? database.transaction {
            for step in steps {
                try database.exec(sql: """
                    INSERT INTO scheduled_step (step_id, plan_id, recipe_name, instruction, step, start_time, duration,
                        date, is_automatic_recurrence, serving_scale)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, parameters: [
                        step.id.map { SQLValue.text($0.uuidString) } ?? SQLValue.null,
                        step.planID.map { SQLValue.text($0.uuidString) } ?? SQLValue.null,
                        .text(step.recipeName),
                        .text(step.instruction),
                        .real(step.step),
                        .long(Int64(step.startTime)),
                        .long(Int64(step.duration)),
                        // Seconds since 2001, the way Date keeps them, so a
                        // date comes back exactly as it went in.
                        .real(step.date.timeIntervalSinceReferenceDate),
                        .long(step.isAutomaticRecurrence ? 1 : 0),
                        .real(step.servingScale),
                    ])
            }
        }
    }

    public func removeSteps(recipeName: String) {
        _ = try? database.exec(sql: "DELETE FROM scheduled_step WHERE recipe_name = ?", parameters: [.text(recipeName)])
    }

    public func allSteps() -> [StoredScheduledStep] {
        select(where: nil, [])
    }

    public func removeStep(key: String) {
        guard let rowID = Int64(key) else { return }
        _ = try? database.exec(sql: "DELETE FROM scheduled_step WHERE id = ?", parameters: [.long(rowID)])
    }

    // MARK: Helpers

    private func select(where condition: String?, _ parameters: [SQLValue]) -> [StoredScheduledStep] {
        let filter = condition.map { " WHERE \($0)" } ?? ""
        let rows = (try? database.selectAll(sql: """
            SELECT id, step_id, plan_id, recipe_name, instruction, step, start_time, duration, date,
                is_automatic_recurrence, serving_scale
            FROM scheduled_step\(filter) ORDER BY date, step, id
            """, parameters: parameters)) ?? []
        return rows.map { row in
            StoredScheduledStep(
                key: String(row[0].longValue ?? 0),
                data: ScheduledStepData(id: row[1].textValue.flatMap(UUID.init(uuidString:)),
                                        planID: row[2].textValue.flatMap(UUID.init(uuidString:)),
                                        recipeName: row[3].textValue ?? "",
                                        instruction: row[4].textValue ?? "",
                                        step: row[5].realValue ?? 0,
                                        startTime: Int(row[6].longValue ?? 0),
                                        duration: Int(row[7].longValue ?? 0),
                                        date: Date(timeIntervalSinceReferenceDate: row[8].realValue ?? 0),
                                        isAutomaticRecurrence: (row[9].longValue ?? 0) != 0,
                                        servingScale: row[10].realValue ?? 0))
        }
    }

    private func exists(where condition: String, _ parameters: [SQLValue]) -> Bool {
        let rows = try? database.selectAll(sql: "SELECT 1 FROM scheduled_step WHERE \(condition) LIMIT 1",
                                           parameters: parameters)
        return !(rows ?? []).isEmpty
    }
}
