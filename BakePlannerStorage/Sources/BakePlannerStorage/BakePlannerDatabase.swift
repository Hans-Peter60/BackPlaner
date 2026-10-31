//
//  BakePlannerDatabase.swift
//  BakePlannerStorage
//
//  The one SQLite file the Android app keeps the user's data in, with its
//  schema. All stores share it: SQLite keeps one schema version per file
//  (PRAGMA user_version), and a shopping list refers to recipes.
//

import Foundation
import SkipSQLPlus

public final class BakePlannerDatabase {

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

    /// Closes the file. No store on it can be used afterwards.
    public func close() throws {
        try context.close()
    }

    /// The schema, one step per version. Steps are only ever added at the
    /// end: a database on a device runs the ones it has not run yet.
    private static let migrations: [(SQLContext) throws -> Void] = [
        // 1: recipes (step 3d).
        { database in
            try database.exec(sql: """
                CREATE TABLE recipe (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    firestore_id TEXT,
                    adjusted_on REAL,
                    bake_history_flag INTEGER NOT NULL,
                    name TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    url_link TEXT,
                    prep_time INTEGER NOT NULL,
                    total_weight REAL NOT NULL,
                    tags TEXT NOT NULL,
                    rating INTEGER NOT NULL,
                    recurrence_interval_days INTEGER NOT NULL,
                    image BLOB
                )
                """)
            try database.exec(sql: """
                CREATE TABLE component (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    recipe_id INTEGER NOT NULL REFERENCES recipe(id) ON DELETE CASCADE,
                    name TEXT NOT NULL,
                    number INTEGER NOT NULL
                )
                """)
            try database.exec(sql: """
                CREATE TABLE ingredient (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    component_id INTEGER NOT NULL REFERENCES component(id) ON DELETE CASCADE,
                    name TEXT NOT NULL,
                    number INTEGER NOT NULL,
                    unit TEXT,
                    weight REAL NOT NULL,
                    norm_weight REAL NOT NULL,
                    num INTEGER NOT NULL,
                    denom INTEGER NOT NULL
                )
                """)
            try database.exec(sql: """
                CREATE TABLE instruction (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    recipe_id INTEGER NOT NULL REFERENCES recipe(id) ON DELETE CASCADE,
                    instruction TEXT NOT NULL,
                    step REAL NOT NULL,
                    duration INTEGER NOT NULL,
                    start_time INTEGER NOT NULL,
                    bake_flag INTEGER NOT NULL,
                    component_name TEXT
                )
                """)
            try database.exec(sql: "CREATE INDEX component_recipe ON component(recipe_id)")
            try database.exec(sql: "CREATE INDEX ingredient_component ON ingredient(component_id)")
            try database.exec(sql: "CREATE INDEX instruction_recipe ON instruction(recipe_id)")
            try database.exec(sql: "CREATE INDEX recipe_firestore_id ON recipe(firestore_id)")
        },
        // 2: shopping lists (step 5c). Public recipes are kept by name, as a
        // JSON list like the tags.
        { database in
            try database.exec(sql: """
                CREATE TABLE shopping_list (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    date REAL NOT NULL,
                    public_recipe_names TEXT NOT NULL
                )
                """)
            try database.exec(sql: """
                CREATE TABLE shopping_list_recipe (
                    shopping_list_id INTEGER NOT NULL REFERENCES shopping_list(id) ON DELETE CASCADE,
                    recipe_id INTEGER NOT NULL REFERENCES recipe(id) ON DELETE CASCADE,
                    PRIMARY KEY (shopping_list_id, recipe_id)
                )
                """)
            try database.exec(sql: """
                CREATE TABLE shopping_list_item (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    shopping_list_id INTEGER NOT NULL REFERENCES shopping_list(id) ON DELETE CASCADE,
                    name TEXT NOT NULL,
                    unit TEXT,
                    weight REAL NOT NULL,
                    norm_weight REAL NOT NULL,
                    num INTEGER NOT NULL,
                    denom INTEGER NOT NULL
                )
                """)
            try database.exec(sql: "CREATE INDEX shopping_list_recipe_recipe ON shopping_list_recipe(recipe_id)")
            try database.exec(sql: "CREATE INDEX shopping_list_item_list ON shopping_list_item(shopping_list_id)")
        },
        // 3: bake history (step 6b). Facts not recorded are NULL, as in Core
        // Data: a temperature never measured is not 0 °C. Photos in a table
        // of their own, in their order.
        { database in
            try database.exec(sql: """
                CREATE TABLE bake_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    recipe_id INTEGER NOT NULL REFERENCES recipe(id) ON DELETE CASCADE,
                    date REAL NOT NULL,
                    comment TEXT NOT NULL,
                    room_temperature REAL,
                    dough_temperature REAL,
                    bulk_proof_minutes INTEGER,
                    final_proof_minutes INTEGER,
                    flour TEXT,
                    outcome TEXT
                )
                """)
            try database.exec(sql: """
                CREATE TABLE bake_history_image (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    bake_history_id INTEGER NOT NULL REFERENCES bake_history(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    data BLOB NOT NULL
                )
                """)
            try database.exec(sql: "CREATE INDEX bake_history_recipe ON bake_history(recipe_id)")
            try database.exec(sql: "CREATE INDEX bake_history_image_entry ON bake_history_image(bake_history_id)")
        },
    ]
}
