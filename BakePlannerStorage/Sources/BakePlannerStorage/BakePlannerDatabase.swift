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
        // 4: starter feeding diary (step 7b). Not measured is NULL, as in Core
        // Data: no peak time is not 0 minutes, an untried float test not a
        // failed one.
        { database in
            try database.exec(sql: """
                CREATE TABLE starter_feeding (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    recipe_id INTEGER NOT NULL REFERENCES recipe(id) ON DELETE CASCADE,
                    date REAL NOT NULL,
                    peak_minutes INTEGER,
                    float_test_passed INTEGER,
                    note TEXT
                )
                """)
            try database.exec(sql: "CREATE INDEX starter_feeding_recipe ON starter_feeding(recipe_id)")
        },
        // 5: scheduled steps (step 8b). A plan belongs to its recipe by name,
        // as on iOS, so there is no foreign key; ids are UUID text, NULL for
        // steps stored before they had one.
        { database in
            try database.exec(sql: """
                CREATE TABLE scheduled_step (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    step_id TEXT,
                    plan_id TEXT,
                    recipe_name TEXT NOT NULL,
                    instruction TEXT NOT NULL,
                    step REAL NOT NULL,
                    start_time INTEGER NOT NULL,
                    duration INTEGER NOT NULL,
                    date REAL NOT NULL,
                    is_automatic_recurrence INTEGER NOT NULL,
                    serving_scale REAL NOT NULL
                )
                """)
            try database.exec(sql: "CREATE INDEX scheduled_step_recipe ON scheduled_step(recipe_name)")
            try database.exec(sql: "CREATE INDEX scheduled_step_date ON scheduled_step(date)")
        },
        // 6: recipe variants and the rating of a bake (step 23b). A variant
        // points at its origin; the origin going leaves the variant on its
        // own. A rating never given is NULL, as the other facts.
        { database in
            try database.exec(sql: "ALTER TABLE recipe ADD COLUMN origin_id INTEGER REFERENCES recipe(id) ON DELETE SET NULL")
            try database.exec(sql: "ALTER TABLE recipe ADD COLUMN variant_note TEXT")
            try database.exec(sql: "ALTER TABLE bake_history ADD COLUMN rating INTEGER")
            try database.exec(sql: "CREATE INDEX recipe_origin ON recipe(origin_id)")
        },
        // 7: the room temperature of a feeding (step 26), for the ripeness
        // estimate. NULL when not noted, like the other facts.
        { database in
            try database.exec(sql: "ALTER TABLE starter_feeding ADD COLUMN room_temperature REAL")
        },
        // 8: a step's duration window (step 28), the shortest and the
        // longest it may take in minutes. Both NULL without a window.
        { database in
            try database.exec(sql: "ALTER TABLE instruction ADD COLUMN min_duration INTEGER")
            try database.exec(sql: "ALTER TABLE instruction ADD COLUMN max_duration INTEGER")
        },
        // 9: a step's oven settings (step 35): degrees Celsius, the
        // temperature the heat falls to, steam (0/1). NULL when not set.
        { database in
            try database.exec(sql: "ALTER TABLE instruction ADD COLUMN oven_temperature INTEGER")
            try database.exec(sql: "ALTER TABLE instruction ADD COLUMN oven_falling_temperature INTEGER")
            try database.exec(sql: "ALTER TABLE instruction ADD COLUMN oven_steam INTEGER")
        },
    ]
}
