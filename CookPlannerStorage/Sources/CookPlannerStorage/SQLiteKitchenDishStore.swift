//
//  SQLiteKitchenDishStore.swift
//  CookPlannerStorage
//
//  The cook's dishes kept in SQLite — the KitchenDishStore of the
//  CookPlanner app. Tables dish, step and step_dependency (schema in
//  CookPlannerDatabase). A dish is written whole: its row, then its steps
//  in order, then every step's predecessors in order, in one transaction.
//

import BakePlannerCore
import Foundation
import SkipSQLPlus

public final class SQLiteKitchenDishStore: KitchenDishStore {

    public let file: CookPlannerDatabase
    private var database: SQLContext { file.context }

    /// The store on the database file at `path`, created when missing; in
    /// memory only for `nil`.
    public convenience init(path: String?) throws {
        self.init(file: try CookPlannerDatabase(path: path))
    }

    public init(file: CookPlannerDatabase) {
        self.file = file
    }

    public func close() throws {
        try file.close()
    }

    // MARK: KitchenDishStore

    public func dishes() throws -> [KitchenDish] {
        let rows = try database.selectAll(sql: "SELECT id, name, source, servings, created_at FROM dish")
        return try rows.map { try dish(from: $0) }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
    }

    public func dish(id: String) throws -> KitchenDish? {
        guard let row = try database.selectAll(sql: "SELECT id, name, source, servings, created_at FROM dish WHERE id = ?",
                                               parameters: [.text(id)]).first else { return nil }
        return try dish(from: row)
    }

    public func save(_ dish: KitchenDish) throws {
        guard !dish.id.isEmpty, !dish.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KitchenDishStoreError.incomplete
        }
        try database.savepoint {
            try database.exec(sql: "DELETE FROM step_dependency WHERE dish_id = ?", parameters: [.text(dish.id)])
            try database.exec(sql: "DELETE FROM step WHERE dish_id = ?", parameters: [.text(dish.id)])
            try database.exec(sql: """
                INSERT OR REPLACE INTO dish (id, name, source, servings, created_at) VALUES (?, ?, ?, ?, ?)
                """, parameters: [
                    .text(dish.id),
                    .text(dish.name),
                    .text(dish.source.rawValue),
                    dish.servings.map { SQLValue.long(Int64($0)) } ?? SQLValue.null,
                    dish.createdAt.map { SQLValue.real($0.timeIntervalSinceReferenceDate) } ?? SQLValue.null,
                ])
            for (position, task) in dish.tasks.enumerated() {
                try database.exec(sql: """
                    INSERT INTO step (dish_id, id, position, name, component, hands_minutes, unattended_minutes,
                                      station, max_wait, window_min, window_max, oven_temperature)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, parameters: [
                        .text(dish.id),
                        .text(task.id),
                        .long(Int64(position)),
                        .text(task.name),
                        .text(task.component),
                        .long(Int64(task.handsMinutes)),
                        .long(Int64(task.unattendedMinutes)),
                        task.station.map { SQLValue.text($0.rawValue) } ?? SQLValue.null,
                        task.maxWait.map { SQLValue.long(Int64($0)) } ?? SQLValue.null,
                        task.unattendedWindow.map { SQLValue.long(Int64($0.lowerBound)) } ?? SQLValue.null,
                        task.unattendedWindow.map { SQLValue.long(Int64($0.upperBound)) } ?? SQLValue.null,
                        task.ovenTemperature.map { SQLValue.long(Int64($0)) } ?? SQLValue.null,
                    ])
                for (order, after) in task.after.enumerated() {
                    try database.exec(sql: """
                        INSERT INTO step_dependency (dish_id, step_id, position, after_id) VALUES (?, ?, ?, ?)
                        """, parameters: [.text(dish.id), .text(task.id), .long(Int64(order)), .text(after)])
                }
            }
        }
    }

    public func delete(id: String) throws {
        try database.exec(sql: "DELETE FROM dish WHERE id = ?", parameters: [.text(id)])
    }

    // MARK: Reading

    private func dish(from row: [SQLValue]) throws -> KitchenDish {
        let id = row[0].textValue ?? ""
        let dependencies = try database.selectAll(sql: """
            SELECT step_id, after_id FROM step_dependency WHERE dish_id = ? ORDER BY step_id, position
            """, parameters: [.text(id)])
        var afterByStep = [String: [String]]()
        for dependency in dependencies {
            afterByStep[dependency[0].textValue ?? "", default: []].append(dependency[1].textValue ?? "")
        }
        let steps = try database.selectAll(sql: """
            SELECT id, name, component, hands_minutes, unattended_minutes, station, max_wait, window_min, window_max,
                   oven_temperature
            FROM step WHERE dish_id = ? ORDER BY position
            """, parameters: [.text(id)])
        let tasks = steps.map { step -> KitchenTask in
            let stepID = step[0].textValue ?? ""
            var window: ClosedRange<Int>?
            if let low = step[7].longValue, let high = step[8].longValue, low <= high {
                window = Int(low)...Int(high)
            }
            return KitchenTask(id: stepID, name: step[1].textValue ?? "", component: step[2].textValue ?? "",
                               hands: Int(step[3].longValue ?? 0), unattended: Int(step[4].longValue ?? 0),
                               station: step[5].textValue.flatMap(KitchenStation.init(rawValue:)),
                               after: afterByStep[stepID] ?? [],
                               maxWait: step[6].longValue.map { Int($0) }, window: window,
                               ovenTemperature: step[9].longValue.map { Int($0) })
        }
        return KitchenDish(id: id, name: row[1].textValue ?? "",
                           source: KitchenDishSource(rawValue: row[2].textValue ?? "") ?? .manual,
                           servings: row[3].longValue.map { Int($0) },
                           createdAt: row[4].realValue.map { Date(timeIntervalSinceReferenceDate: $0) },
                           tasks: tasks)
    }
}
