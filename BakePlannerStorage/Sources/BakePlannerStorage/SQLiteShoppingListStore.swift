//
//  SQLiteShoppingListStore.swift
//  BakePlannerStorage
//
//  The user's shopping lists kept in SQLite — the Android side of
//  ShoppingListStore. Tables shopping_list, shopping_list_item and
//  shopping_list_recipe (schema in BakePlannerDatabase), in the same file
//  as the recipes: removing a recipe takes it off its lists, removing a
//  list takes its lines with it.
//

import BakePlannerCore
import Foundation
import SkipSQLPlus

public final class SQLiteShoppingListStore: ShoppingListStore {

    private let file: BakePlannerDatabase
    private var database: SQLContext { file.context }

    /// The store in an open database file — the one the recipes are kept
    /// in (`SQLiteRecipeStore.file`), so lists can refer to them.
    public init(file: BakePlannerDatabase) {
        self.file = file
    }

    // MARK: ShoppingListStore

    public func lists() throws -> [StoredShoppingList] {
        try database.selectAll(sql: "SELECT id, date, public_recipe_names FROM shopping_list ORDER BY date, id")
            .map(list(from:))
    }

    public func list(id: String) throws -> StoredShoppingList? {
        guard let rowID = Int64(id) else { return nil }
        return try database.selectAll(sql: "SELECT id, date, public_recipe_names FROM shopping_list WHERE id = ?",
                                      parameters: [.long(rowID)])
            .first.map(list(from:))
    }

    public func addList(on date: Date) throws -> StoredShoppingList {
        try database.exec(sql: "INSERT INTO shopping_list (date, public_recipe_names) VALUES (?, ?)",
                          parameters: [.real(date.timeIntervalSinceReferenceDate), .text(try Self.namesText([]))])
        return StoredShoppingList(id: String(database.lastInsertRowID), date: date)
    }

    public func apply(_ lines: [ShoppingListLine], recipe: ShoppingListRecipe?, toList id: String) throws {
        guard let listID = Int64(id),
              let row = try database.selectAll(sql: "SELECT public_recipe_names FROM shopping_list WHERE id = ?",
                                               parameters: [.long(listID)]).first else {
            throw ShoppingListStoreError.unknownList(id)
        }
        // Checked before anything changes, so a failed call leaves the list
        // as it was.
        var ownRecipeID: Int64?
        if case .own(let recipeID) = recipe {
            guard let rowID = Int64(recipeID),
                  !(try database.selectAll(sql: "SELECT 1 FROM recipe WHERE id = ?",
                                           parameters: [.long(rowID)]).isEmpty) else {
                throw ShoppingListStoreError.unknownRecipe(recipeID)
            }
            ownRecipeID = rowID
        }
        let current = Set(try database.selectAll(sql: "SELECT id FROM shopping_list_item WHERE shopping_list_id = ?",
                                                 parameters: [.long(listID)]).compactMap { $0[0].longValue })

        try database.transaction {
            var kept = Set<Int64>()
            for line in lines {
                if let key = line.key, let itemID = Int64(key), current.contains(itemID) {
                    try write(line, item: itemID)
                    kept.insert(itemID)
                } else {
                    try database.exec(sql: """
                        INSERT INTO shopping_list_item (shopping_list_id, name, unit, weight, norm_weight, num, denom)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """, parameters: [.long(listID)] + Self.values(of: line))
                }
            }
            for itemID in current where !kept.contains(itemID) {
                try database.exec(sql: "DELETE FROM shopping_list_item WHERE id = ?", parameters: [.long(itemID)])
            }

            if let ownRecipeID {
                try database.exec(sql: """
                    INSERT OR IGNORE INTO shopping_list_recipe (shopping_list_id, recipe_id) VALUES (?, ?)
                    """, parameters: [.long(listID), .long(ownRecipeID)])
            } else if case .publicRecipe(let name) = recipe {
                let names = ShoppingListRecipeNames.adding(name, to: try Self.names(from: row[0].textValue))
                try database.exec(sql: "UPDATE shopping_list SET public_recipe_names = ? WHERE id = ?",
                                  parameters: [.text(try Self.namesText(names)), .long(listID)])
            }
        }
    }

    public func update(_ item: StoredShoppingListItem) throws {
        guard let itemID = Int64(item.id),
              !(try database.selectAll(sql: "SELECT 1 FROM shopping_list_item WHERE id = ?",
                                       parameters: [.long(itemID)]).isEmpty) else {
            throw ShoppingListStoreError.unknownItem(item.id)
        }
        try write(item.line, item: itemID)
    }

    public func deleteItem(id: String) throws {
        guard let itemID = Int64(id) else { return }
        try database.exec(sql: "DELETE FROM shopping_list_item WHERE id = ?", parameters: [.long(itemID)])
    }

    public func delete(id: String) throws {
        guard let listID = Int64(id) else { return }
        try database.exec(sql: "DELETE FROM shopping_list WHERE id = ?", parameters: [.long(listID)])
    }

    // MARK: Helpers

    private func write(_ line: ShoppingListLine, item itemID: Int64) throws {
        try database.exec(sql: """
            UPDATE shopping_list_item SET name = ?, unit = ?, weight = ?, norm_weight = ?, num = ?, denom = ?
            WHERE id = ?
            """, parameters: Self.values(of: line) + [.long(itemID)])
    }

    private func list(from row: [SQLValue]) throws -> StoredShoppingList {
        let listID = row[0].longValue ?? 0
        let publicNames = try Self.names(from: row[2].textValue)
        let recipes = try database.selectAll(sql: """
            SELECT recipe.id, recipe.name FROM shopping_list_recipe
            JOIN recipe ON recipe.id = shopping_list_recipe.recipe_id
            WHERE shopping_list_recipe.shopping_list_id = ?
            """, parameters: [.long(listID)])
        let items = try database.selectAll(sql: """
            SELECT id, name, unit, weight, norm_weight, num, denom FROM shopping_list_item
            WHERE shopping_list_id = ? ORDER BY id
            """, parameters: [.long(listID)])
            .map { item in
                StoredShoppingListItem(id: String(item[0].longValue ?? 0),
                                       name: item[1].textValue ?? "",
                                       unit: item[2].textValue,
                                       weight: item[3].realValue ?? 0,
                                       normWeight: item[4].realValue ?? 0,
                                       num: Int(item[5].longValue ?? 0),
                                       denom: Int(item[6].longValue ?? 0))
            }
        return StoredShoppingList(
            id: String(listID),
            date: Date(timeIntervalSinceReferenceDate: row[1].realValue ?? 0),
            recipeIDs: recipes.map { String($0[0].longValue ?? 0) }.sorted(),
            publicRecipeNames: publicNames,
            recipeNames: (recipes.map { $0[1].textValue ?? "" } + publicNames).sorted(),
            // By name in Swift's String order, as Core Data's ingredientsArray
            // has them; SQLite would compare differently. Stable, so lines of
            // the same name stay in the order they were added.
            items: items.enumerated().sorted { first, second in
                first.element.name != second.element.name
                    ? first.element.name < second.element.name
                    : first.offset < second.offset
            }.map(\.element))
    }

    private static func values(of line: ShoppingListLine) -> [SQLValue] {
        [.text(line.name), line.unit.map { SQLValue.text($0) } ?? SQLValue.null, .real(line.weight), .real(line.normWeight),
         .long(Int64(line.num)), .long(Int64(line.denom))]
    }

    private static func namesText(_ names: [String]) throws -> String {
        String(decoding: try JSONEncoder().encode(names), as: UTF8.self)
    }

    private static func names(from text: String?) throws -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return try JSONDecoder().decode([String].self, from: Data(text.utf8))
    }
}
