//
//  ShoppingListStore.swift
//  BakePlannerCore
//
//  The user's shopping lists, wherever they are kept: Core Data with iCloud
//  on iOS, SQLite on Android. What goes on a list and how it joins what is
//  there already is ShoppingListBuilder's business; a store only keeps the
//  result.
//

import Foundation

/// One line of a shopping list as a store holds it.
public struct StoredShoppingListItem: Equatable {
    /// The store's own key for the line.
    public var id: String
    public var name: String
    public var unit: String?
    public var weight: Double
    /// The amount in its base unit, kept in step with the amount: lines are
    /// merged and converted by it when another recipe is added.
    public var normWeight: Double
    public var num: Int
    public var denom: Int

    public init(id: String, name: String, unit: String?, weight: Double, normWeight: Double, num: Int, denom: Int) {
        self.id = id
        self.name = name
        self.unit = unit
        self.weight = weight
        self.normWeight = normWeight
        self.num = num
        self.denom = denom
    }

    /// The line as ShoppingListBuilder takes it, keyed by `id`.
    public var line: ShoppingListLine {
        ShoppingListLine(key: id, name: name, unit: unit, weight: weight, normWeight: normWeight,
                         num: num, denom: denom)
    }
}

/// One shopping list as a store holds it.
public struct StoredShoppingList: Equatable {
    /// The store's own key for the list.
    public var id: String
    public var date: Date
    /// The keys of the user's own recipes on the list (keys of the
    /// RecipeStore kept beside this store), sorted. A recipe deleted later
    /// drops out; its ingredients stay on the list.
    public var recipeIDs: [String]
    /// Public recipes on the list, by name: there is no own object to refer
    /// to. In the order they were added.
    public var publicRecipeNames: [String]
    /// The names of all recipes on the list, own and public, sorted — what
    /// the list shows under its date.
    public var recipeNames: [String]
    /// The lines, ordered by name.
    public var items: [StoredShoppingListItem]

    public init(id: String, date: Date, recipeIDs: [String] = [], publicRecipeNames: [String] = [],
                recipeNames: [String] = [], items: [StoredShoppingListItem] = []) {
        self.id = id
        self.date = date
        self.recipeIDs = recipeIDs
        self.publicRecipeNames = publicRecipeNames
        self.recipeNames = recipeNames
        self.items = items
    }
}

/// The recipe whose ingredients are put on a list.
public enum ShoppingListRecipe: Equatable {
    /// One of the user's own recipes, by its key in the RecipeStore.
    case own(id: String)
    /// A public recipe, by name.
    case publicRecipe(name: String)
}

/// Where the shopping lists are kept, next to a RecipeStore on the same
/// storage, so a list can refer to the user's own recipes.
///
/// Lists are ordered by date, oldest first; their lines by name
/// (`String` order, as the iOS app has always kept them).
public protocol ShoppingListStore {
    /// Every list, oldest first.
    func lists() throws -> [StoredShoppingList]
    /// The list with this key.
    func list(id: String) throws -> StoredShoppingList?
    /// Keeps a new, empty list for `date`.
    func addList(on date: Date) throws -> StoredShoppingList
    /// Makes the lines of list `id` what `lines` says, in one go: a line
    /// whose key is one of the list's lines changes that line, a line
    /// without a key becomes a new one, and the list's lines left out are
    /// removed. `recipe`, when given, is recorded on the list (once).
    func apply(_ lines: [ShoppingListLine], recipe: ShoppingListRecipe?, toList id: String) throws
    /// Replaces one line: name, unit and amounts.
    func update(_ item: StoredShoppingListItem) throws
    /// Removes one line. Nothing happens for an unknown key.
    func deleteItem(id: String) throws
    /// Removes the list with its lines; the recipes stay. Nothing happens
    /// for an unknown key.
    func delete(id: String) throws
}

/// The names of the public recipes on a list, kept the way the iOS app has
/// always kept them: trimmed, without empty names and without duplicates.
public enum ShoppingListRecipeNames {
    public static func adding(_ name: String, to names: [String]) -> [String] {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !names.contains(cleaned) else { return names }
        return names + [cleaned]
    }
}

public enum ShoppingListStoreError: Error, Equatable {
    case unknownList(String)
    case unknownItem(String)
    /// An own recipe the RecipeStore beside this store does not have.
    case unknownRecipe(String)
}

extension ShoppingListStore {

    /// Puts `entries` — already sifted and scaled, see
    /// ``ShoppingListBuilder/entriesToBuy(_:scale:)`` — on list `id` and
    /// records `recipe` there.
    public func add(_ entries: [ShoppingListEntry], from recipe: ShoppingListRecipe, toList id: String) throws {
        guard let list = try list(id: id) else { throw ShoppingListStoreError.unknownList(id) }
        let lines = ShoppingListBuilder.adding(entries, to: list.items.map(\.line))
        try apply(lines, recipe: recipe, toList: id)
    }

    /// The list for the day of `date`, if there is one: a recipe added for
    /// a day that already has a list goes on that list. Of several lists on
    /// that day, the latest, as the iOS app has always picked.
    public func list(onSameDayAs date: Date, calendar: Calendar = .current) throws -> StoredShoppingList? {
        try lists().last { calendar.isDate($0.date, inSameDayAs: date) }
    }
}
