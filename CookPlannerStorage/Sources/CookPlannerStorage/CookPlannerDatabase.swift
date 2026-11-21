//
//  CookPlannerDatabase.swift
//  CookPlannerStorage
//
//  The one SQLite file the CookPlanner app keeps the cook's dishes in, with
//  its schema. SQLite keeps one schema version per file (PRAGMA
//  user_version); steps are only ever added at the end of the list, and a
//  database on a device runs the ones it has not run yet.
//

import Foundation
import SkipSQLPlus

public final class CookPlannerDatabase {

    let context: SQLContext

    /// The database file at `path`, created when missing and brought to the
    /// current schema; in memory only for `nil`.
    public init(path: String?) throws {
        if let path {
            context = try SQLContext(path: path, flags: [.create, .readWrite], configuration: .plus)
        } else {
            context = SQLContext(configuration: .plus)
        }
        try context.exec(sql: "PRAGMA foreign_keys = ON")
        try context.migrate(migrations: Self.migrations)
    }

    /// Runs `work` as one transaction: all of it is kept, or — when it
    /// throws — none of it.
    public func atomically<T>(_ work: () throws -> T) throws -> T {
        try context.savepoint(work)
    }

    /// Closes the file. No store on it can be used afterwards.
    public func close() throws {
        try context.close()
    }

    private static let migrations: [(SQLContext) throws -> Void] = [
        // 1: dishes with their steps and the steps' dependencies. Ids are
        // the app's text ids (UUIDs, or the examples' names); a step's id is
        // unique within its dish. Dates as seconds since 2001, NULL when
        // not known; a window needs both ends; station is "burner", "oven"
        // or NULL.
        { database in
            try database.exec(sql: """
                CREATE TABLE dish (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    source TEXT NOT NULL,
                    servings INTEGER,
                    created_at REAL
                )
                """)
            try database.exec(sql: """
                CREATE TABLE step (
                    dish_id TEXT NOT NULL REFERENCES dish(id) ON DELETE CASCADE,
                    id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    name TEXT NOT NULL,
                    component TEXT NOT NULL,
                    hands_minutes INTEGER NOT NULL,
                    unattended_minutes INTEGER NOT NULL,
                    station TEXT,
                    max_wait INTEGER,
                    window_min INTEGER,
                    window_max INTEGER,
                    oven_temperature INTEGER,
                    PRIMARY KEY (dish_id, id)
                )
                """)
            try database.exec(sql: """
                CREATE TABLE step_dependency (
                    dish_id TEXT NOT NULL REFERENCES dish(id) ON DELETE CASCADE,
                    step_id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    after_id TEXT NOT NULL,
                    PRIMARY KEY (dish_id, step_id, position)
                )
                """)
            try database.exec(sql: "CREATE INDEX step_dish ON step(dish_id, position)")
            try database.exec(sql: "CREATE INDEX step_dependency_step ON step_dependency(dish_id, step_id)")
        },
        // 2: the dish's ingredients, and which of them a step uses. An
        // amount is NULL when the recipe gives none; unit, component and
        // note are empty text rather than NULL.
        { database in
            try database.exec(sql: """
                CREATE TABLE ingredient (
                    dish_id TEXT NOT NULL REFERENCES dish(id) ON DELETE CASCADE,
                    id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    name TEXT NOT NULL,
                    amount REAL,
                    unit TEXT NOT NULL,
                    component TEXT NOT NULL,
                    note TEXT NOT NULL,
                    PRIMARY KEY (dish_id, id)
                )
                """)
            try database.exec(sql: """
                CREATE TABLE step_ingredient (
                    dish_id TEXT NOT NULL REFERENCES dish(id) ON DELETE CASCADE,
                    step_id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    ingredient_id TEXT NOT NULL,
                    PRIMARY KEY (dish_id, step_id, position)
                )
                """)
            try database.exec(sql: "CREATE INDEX ingredient_dish ON ingredient(dish_id, position)")
            try database.exec(sql: "CREATE INDEX step_ingredient_step ON step_ingredient(dish_id, step_id)")
        },
    ]
}

extension SQLContext {

    /// A transaction that may run inside another: SQLite refuses a BEGIN
    /// within a transaction, but nests savepoints, and a savepoint outside
    /// any transaction starts one.
    func savepoint<T>(_ work: () throws -> T) throws -> T {
        try exec(sql: "SAVEPOINT cookplanner")
        do {
            let result = try work()
            try exec(sql: "RELEASE SAVEPOINT cookplanner")
            return result
        } catch {
            try? exec(sql: "ROLLBACK TO SAVEPOINT cookplanner")
            try? exec(sql: "RELEASE SAVEPOINT cookplanner")
            throw error
        }
    }
}
