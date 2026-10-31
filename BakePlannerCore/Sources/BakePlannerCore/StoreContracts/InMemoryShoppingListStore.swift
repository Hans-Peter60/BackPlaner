//
//  InMemoryShoppingListStore.swift
//  BakePlannerCore
//
//  A ShoppingListStore that keeps everything in memory, next to an
//  InMemoryRecipeStore: the reference the contract is checked against
//  first, and a stand-in for tests.
//

import Foundation

public final class InMemoryShoppingListStore: ShoppingListStore {

    private struct List {
        var id: String
        var date: Date
        var recipeIDs: [String]
        var publicRecipeNames: [String]
        var items: [StoredShoppingListItem]
    }

    private let recipes: RecipeStore
    private var stored: [String: List] = [:]
    private var nextID = 1

    /// `recipes` is the store the lists' own recipes are kept in.
    public init(recipes: RecipeStore) {
        self.recipes = recipes
    }

    public func lists() throws -> [StoredShoppingList] {
        try stored.values
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.id < $1.id }
            .map(read)
    }

    public func list(id: String) throws -> StoredShoppingList? {
        try stored[id].map(read)
    }

    public func addList(on date: Date) throws -> StoredShoppingList {
        let list = List(id: newKey(), date: date, recipeIDs: [], publicRecipeNames: [], items: [])
        stored[list.id] = list
        return try read(list)
    }

    public func apply(_ lines: [ShoppingListLine], recipe: ShoppingListRecipe?, toList id: String) throws {
        guard var list = stored[id] else { throw ShoppingListStoreError.unknownList(id) }

        switch recipe {
        case .own(let recipeID):
            guard try recipes.recipe(id: recipeID) != nil else {
                throw ShoppingListStoreError.unknownRecipe(recipeID)
            }
            if !list.recipeIDs.contains(recipeID) { list.recipeIDs.append(recipeID) }
        case .publicRecipe(let name):
            list.publicRecipeNames = ShoppingListRecipeNames.adding(name, to: list.publicRecipeNames)
        case nil:
            break
        }

        let current = Set(list.items.map(\.id))
        list.items = lines.map { line in
            let key = line.key.flatMap { current.contains($0) ? $0 : nil } ?? newKey()
            return StoredShoppingListItem(id: key, name: line.name, unit: line.unit, weight: line.weight,
                                          normWeight: line.normWeight, num: line.num, denom: line.denom)
        }
        stored[id] = list
    }

    public func update(_ item: StoredShoppingListItem) throws {
        guard let listID = stored.values.first(where: { list in list.items.contains { $0.id == item.id } })?.id,
              let index = stored[listID]?.items.firstIndex(where: { $0.id == item.id }) else {
            throw ShoppingListStoreError.unknownItem(item.id)
        }
        stored[listID]?.items[index] = item
    }

    public func deleteItem(id: String) throws {
        for key in stored.keys {
            stored[key]?.items.removeAll { $0.id == id }
        }
    }

    public func delete(id: String) throws {
        stored[id] = nil
    }

    // MARK: Helpers

    private func newKey() -> String {
        defer { nextID += 1 }
        return "memory-list-\(nextID)"
    }

    private func read(_ list: List) throws -> StoredShoppingList {
        // A recipe deleted since it was added drops out, as Core Data's
        // nullify rule has it.
        let own = try list.recipeIDs.compactMap { try recipes.recipe(id: $0) }
        return StoredShoppingList(
            id: list.id,
            date: list.date,
            recipeIDs: own.map(\.id).sorted(),
            publicRecipeNames: list.publicRecipeNames,
            recipeNames: (own.map(\.content.name) + list.publicRecipeNames).sorted(),
            items: list.items.sorted { $0.name != $1.name ? $0.name < $1.name : $0.id < $1.id })
    }
}
