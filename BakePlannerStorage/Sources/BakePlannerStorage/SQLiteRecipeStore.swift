//
//  SQLiteRecipeStore.swift
//  BakePlannerStorage
//
//  The user's own recipes kept in SQLite — the Android side of RecipeStore.
//  One table per level, as in the iOS Core Data model: recipe, component,
//  ingredient, instruction. Removing a recipe removes its parts.
//

import BakePlannerCore
import Foundation
import SkipSQLPlus

public final class SQLiteRecipeStore: RecipeStore {

    private let database: SQLContext

    /// The store in the database file at `path`, created when missing; in
    /// memory only for `nil`.
    public init(path: String?) throws {
        if let path {
            database = try SQLContext(path: path, flags: [.create, .readWrite], configuration: .plus)
        } else {
            database = SQLContext(configuration: .plus)
        }
        try database.exec(sql: "PRAGMA foreign_keys = ON")
        try database.migrate(migrations: Self.migrations)
    }

    /// Closes the database file. The store cannot be used afterwards.
    public func close() throws {
        try database.close()
    }

    /// The schema, one step per version. Steps are only ever added at the
    /// end: a database on a device runs the ones it has not run yet.
    private static let migrations: [(SQLContext) throws -> Void] = [
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
    ]

    // MARK: RecipeStore

    public func recipes(includingImages: Bool) throws -> [StoredRecipe] {
        try database.selectAll(sql: "SELECT \(Self.recipeColumns) FROM recipe")
            .map { try recipe(from: $0, includingImage: includingImages) }
            .sorted { $0.content.name.localizedStandardCompare($1.content.name) == .orderedAscending }
    }

    public func recipe(id: String) throws -> StoredRecipe? {
        guard let rowID = Int64(id) else { return nil }
        return try database.selectAll(sql: "SELECT \(Self.recipeColumns) FROM recipe WHERE id = ?",
                                      parameters: [.long(rowID)])
            .first.map { try recipe(from: $0, includingImage: true) }
    }

    public func recipe(firestoreId: String) throws -> StoredRecipe? {
        try database.selectAll(sql: "SELECT \(Self.recipeColumns) FROM recipe WHERE firestore_id = ? ORDER BY id LIMIT 1",
                               parameters: [.text(firestoreId)])
            .first.map { try recipe(from: $0, includingImage: true) }
    }

    public func add(_ content: RecipeExportData, firestoreId: String?, adjustedOn: Date?,
                    bakeHistoryFlag: Bool) throws -> StoredRecipe {
        try database.transaction {
            try insert(content, firestoreId: firestoreId, adjustedOn: adjustedOn, bakeHistoryFlag: bakeHistoryFlag)
        }
    }

    public func add(contentsOf contents: [RecipeExportData]) throws -> [StoredRecipe] {
        try database.transaction {
            try contents.map { try insert($0, firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false) }
        }
    }

    public func update(_ recipe: StoredRecipe) throws {
        guard let rowID = Int64(recipe.id), try exists(rowID) else {
            throw RecipeStoreError.unknownRecipe(recipe.id)
        }
        let content = recipe.content
        try database.transaction {
            try database.exec(sql: """
                UPDATE recipe SET firestore_id = ?, adjusted_on = ?, bake_history_flag = ?, name = ?, summary = ?,
                    url_link = ?, prep_time = ?, total_weight = ?, tags = ?, rating = ?, recurrence_interval_days = ?
                WHERE id = ?
                """, parameters: [
                    Self.value(recipe.firestoreId), Self.value(recipe.adjustedOn), Self.value(recipe.bakeHistoryFlag),
                    .text(content.name), .text(content.summary), Self.value(content.urlLink),
                    .long(Int64(content.prepTime)), .real(content.totalWeight), .text(try Self.tagsText(content.tags)),
                    .long(Int64(content.rating)), .long(Int64(content.recurrenceIntervalDays)), .long(rowID),
                ])
            try database.exec(sql: "DELETE FROM component WHERE recipe_id = ?", parameters: [.long(rowID)])
            try database.exec(sql: "DELETE FROM instruction WHERE recipe_id = ?", parameters: [.long(rowID)])
            try insertParts(of: content, recipe: rowID)
        }
    }

    public func setImage(_ image: Data?, forRecipe id: String) throws {
        guard let rowID = Int64(id), try exists(rowID) else { throw RecipeStoreError.unknownRecipe(id) }
        try database.exec(sql: "UPDATE recipe SET image = ? WHERE id = ?",
                          parameters: [Self.value(image), .long(rowID)])
    }

    public func delete(id: String) throws {
        guard let rowID = Int64(id) else { return }
        try database.exec(sql: "DELETE FROM recipe WHERE id = ?", parameters: [.long(rowID)])
    }

    // MARK: Writing

    private func insert(_ content: RecipeExportData, firestoreId: String?, adjustedOn: Date?,
                        bakeHistoryFlag: Bool) throws -> StoredRecipe {
        try database.exec(sql: """
            INSERT INTO recipe (firestore_id, adjusted_on, bake_history_flag, name, summary, url_link, prep_time,
                total_weight, tags, rating, recurrence_interval_days, image)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, parameters: [
                Self.value(firestoreId), Self.value(adjustedOn), Self.value(bakeHistoryFlag),
                .text(content.name), .text(content.summary), Self.value(content.urlLink),
                .long(Int64(content.prepTime)), .real(content.totalWeight), .text(try Self.tagsText(content.tags)),
                .long(Int64(content.rating)), .long(Int64(content.recurrenceIntervalDays)), Self.value(content.image),
            ])
        let rowID = database.lastInsertRowID
        try insertParts(of: content, recipe: rowID)
        return StoredRecipe(id: String(rowID), firestoreId: firestoreId, adjustedOn: adjustedOn,
                            bakeHistoryFlag: bakeHistoryFlag, content: content.inStoreOrder)
    }

    private func insertParts(of content: RecipeExportData, recipe rowID: Int64) throws {
        for component in content.components {
            try database.exec(sql: "INSERT INTO component (recipe_id, name, number) VALUES (?, ?, ?)",
                              parameters: [.long(rowID), .text(component.name), .long(Int64(component.number))])
            let componentID = database.lastInsertRowID
            for ingredient in component.ingredients {
                try database.exec(sql: """
                    INSERT INTO ingredient (component_id, name, number, unit, weight, norm_weight, num, denom)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, parameters: [
                        .long(componentID), .text(ingredient.name), .long(Int64(ingredient.number)),
                        Self.value(ingredient.unit), .real(ingredient.weight), .real(ingredient.normWeight),
                        .long(Int64(ingredient.num)), .long(Int64(ingredient.denom)),
                    ])
            }
        }
        for instruction in content.instructions {
            try database.exec(sql: """
                INSERT INTO instruction (recipe_id, instruction, step, duration, start_time, bake_flag, component_name)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, parameters: [
                    .long(rowID), .text(instruction.instruction), .real(instruction.step),
                    .long(Int64(instruction.duration)), .long(Int64(instruction.startTime)),
                    Self.value(instruction.bakeFlag), Self.value(instruction.componentName),
                ])
        }
    }

    private func exists(_ rowID: Int64) throws -> Bool {
        !(try database.selectAll(sql: "SELECT 1 FROM recipe WHERE id = ?", parameters: [.long(rowID)]).isEmpty)
    }

    // MARK: Reading

    private static let recipeColumns = """
        id, firestore_id, adjusted_on, bake_history_flag, name, summary, url_link, prep_time, total_weight, tags,
        rating, recurrence_interval_days, image
        """

    private func recipe(from row: [SQLValue], includingImage: Bool) throws -> StoredRecipe {
        let rowID = row[0].longValue ?? 0
        let content = RecipeExportData(
            name: row[4].textValue ?? "",
            summary: row[5].textValue ?? "",
            urlLink: row[6].textValue,
            prepTime: Int(row[7].longValue ?? 0),
            totalWeight: row[8].realValue ?? 0,
            tags: try Self.tags(from: row[9].textValue),
            rating: Int(row[10].longValue ?? 0),
            recurrenceIntervalDays: Int(row[11].longValue ?? 0),
            image: includingImage ? row[12].blobValue : nil,
            components: try components(of: rowID),
            instructions: try instructions(of: rowID))
        return StoredRecipe(id: String(rowID),
                            firestoreId: row[1].textValue,
                            adjustedOn: row[2].realValue.map { Date(timeIntervalSinceReferenceDate: $0) },
                            bakeHistoryFlag: (row[3].longValue ?? 0) != 0,
                            content: content)
    }

    private func components(of rowID: Int64) throws -> [RecipeExportComponent] {
        try database.selectAll(sql: "SELECT id, name, number FROM component WHERE recipe_id = ? ORDER BY number, id",
                               parameters: [.long(rowID)])
            .map { row in
                RecipeExportComponent(name: row[1].textValue ?? "",
                                      number: Int(row[2].longValue ?? 0),
                                      ingredients: try ingredients(of: row[0].longValue ?? 0))
            }
    }

    private func ingredients(of componentID: Int64) throws -> [RecipeExportIngredient] {
        try database.selectAll(sql: """
            SELECT name, number, unit, weight, norm_weight, num, denom FROM ingredient
            WHERE component_id = ? ORDER BY number, id
            """, parameters: [.long(componentID)])
            .map { row in
                RecipeExportIngredient(name: row[0].textValue ?? "",
                                       number: Int(row[1].longValue ?? 0),
                                       unit: row[2].textValue,
                                       weight: row[3].realValue ?? 0,
                                       normWeight: row[4].realValue ?? 0,
                                       num: Int(row[5].longValue ?? 0),
                                       denom: Int(row[6].longValue ?? 0))
            }
    }

    private func instructions(of rowID: Int64) throws -> [RecipeExportInstruction] {
        try database.selectAll(sql: """
            SELECT instruction, step, duration, start_time, bake_flag, component_name FROM instruction
            WHERE recipe_id = ? ORDER BY step, id
            """, parameters: [.long(rowID)])
            .map { row in
                RecipeExportInstruction(instruction: row[0].textValue ?? "",
                                        step: row[1].realValue ?? 0,
                                        duration: Int(row[2].longValue ?? 0),
                                        startTime: Int(row[3].longValue ?? 0),
                                        bakeFlag: (row[4].longValue ?? 0) != 0,
                                        componentName: row[5].textValue)
            }
    }

    // MARK: Values

    private static func value(_ text: String?) -> SQLValue {
        text.map { .text($0) } ?? .null
    }

    private static func value(_ data: Data?) -> SQLValue {
        // An empty picture is no picture, as in Core Data.
        guard let data, !data.isEmpty else { return .null }
        return .blob(data)
    }

    private static func value(_ date: Date?) -> SQLValue {
        // Seconds since 2001, the way Date keeps them, so a date comes back
        // exactly as it went in.
        date.map { .real($0.timeIntervalSinceReferenceDate) } ?? .null
    }

    private static func value(_ flag: Bool) -> SQLValue {
        .long(flag ? 1 : 0)
    }

    private static func tagsText(_ tags: [String]) throws -> String {
        String(decoding: try JSONEncoder().encode(tags), as: UTF8.self)
    }

    private static func tags(from text: String?) throws -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return try JSONDecoder().decode([String].self, from: Data(text.utf8))
    }
}
