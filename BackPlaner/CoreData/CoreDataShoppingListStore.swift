//
//  CoreDataShoppingListStore.swift
//  BackPlaner
//
//  The user's shopping lists kept in Core Data (and iCloud) — the iOS side
//  of ShoppingListStore. A list is a ShoppingCart, its lines are Ingredient
//  objects of their own (copies, not the recipe's), and keys are object IDs
//  like those of CoreDataRecipeStore.
//

import BakePlannerCore
import CoreData
import Foundation

struct CoreDataShoppingListStore: ShoppingListStore {

    let context: NSManagedObjectContext

    func lists() throws -> [StoredShoppingList] {
        let request = ShoppingCart.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return try context.fetch(request).map(stored)
    }

    func list(id: String) throws -> StoredShoppingList? {
        managedCart(id: id).map(stored)
    }

    func addList(on date: Date) throws -> StoredShoppingList {
        let cart = ShoppingCart(context: context)
        cart.id = UUID()
        cart.date = date
        try save()
        return stored(cart)
    }

    func apply(_ lines: [ShoppingListLine], recipe: ShoppingListRecipe?, toList id: String) throws {
        guard let cart = managedCart(id: id) else { throw ShoppingListStoreError.unknownList(id) }
        // Checked before anything changes, so a failed call leaves the list
        // as it was.
        var ownRecipe: Recipe?
        if case .own(let recipeID) = recipe {
            guard let found: Recipe = existingObject(id: recipeID) else {
                throw ShoppingListStoreError.unknownRecipe(recipeID)
            }
            ownRecipe = found
        }

        cart.apply(lines, in: context)
        if let ownRecipe {
            cart.addToRecipes(ownRecipe)
        } else if case .publicRecipe(let name) = recipe {
            cart.addCloudRecipeName(name)
        }
        try save()
    }

    func update(_ item: StoredShoppingListItem) throws {
        guard let ingredient = managedItem(id: item.id) else { throw ShoppingListStoreError.unknownItem(item.id) }
        ingredient.take(item.line)
        try save()
    }

    func deleteItem(id: String) throws {
        guard let ingredient = managedItem(id: id) else { return }
        context.delete(ingredient)
        try save()
    }

    func delete(id: String) throws {
        guard let cart = managedCart(id: id) else { return }
        context.delete(cart)
        try save()
    }

    // MARK: Helpers

    private func stored(_ cart: ShoppingCart) -> StoredShoppingList {
        let recipes = (cart.recipes as? Set<Recipe> ?? []).filter { !$0.isDeleted }
        let cloudNames = cart.cloudRecipeNamesArray
        return StoredShoppingList(
            id: cart.storeKey,
            date: cart.date,
            recipeIDs: recipes.map(\.storeKey).sorted(),
            publicRecipeNames: cloudNames,
            recipeNames: (recipes.map(\.name) + cloudNames).sorted(),
            items: cart.ingredientsArray.map { ingredient in
                StoredShoppingListItem(id: ingredient.storeKey, name: ingredient.name, unit: ingredient.unit,
                                       weight: ingredient.weight, normWeight: ingredient.normWeight,
                                       num: ingredient.num, denom: ingredient.denom)
            })
    }

    private func managedCart(id: String) -> ShoppingCart? {
        existingObject(id: id)
    }

    /// A line of a shopping list — never an ingredient of a recipe, which
    /// is an Ingredient object too.
    private func managedItem(id: String) -> Ingredient? {
        guard let ingredient: Ingredient = existingObject(id: id),
              ingredient.component == nil,
              (ingredient.shoppingCarts?.count ?? 0) > 0 else { return nil }
        return ingredient
    }

    private func existingObject<Object: NSManagedObject>(id: String) -> Object? {
        // Core Data raises an Objective-C exception, which Swift cannot
        // catch, for a key that is not one of its own URIs at all.
        guard let url = URL(string: id), url.scheme == "x-coredata", url.host() != nil,
              let objectID = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
              let object = try? context.existingObject(with: objectID) as? Object,
              !object.isDeleted else { return nil }
        return object
    }

    private func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}

extension NSManagedObject {
    /// The key a store hands out for this object.
    var storeKey: String { objectID.uriRepresentation().absoluteString }
}

extension ShoppingCart {

    /// Makes the cart's ingredients what `lines` says — the result of
    /// ShoppingListBuilder for lines keyed by `storeKey`: a line with the
    /// key of one of the cart's ingredients changes it, a line without one
    /// gets a new ingredient, and ingredients left out are deleted.
    func apply(_ lines: [ShoppingListLine], in context: NSManagedObjectContext) {
        let ingredients = ingredientsArray
        let byKey = Dictionary(ingredients.map { ($0.storeKey, $0) }, uniquingKeysWith: { first, _ in first })
        var kept = Set<NSManagedObjectID>()

        for line in lines {
            let ingredient: Ingredient
            if let key = line.key, let existing = byKey[key] {
                ingredient = existing
            } else {
                ingredient = Ingredient(context: context)
                ingredient.id = UUID()
                ingredient.number = 0
                addToIngredients(ingredient)
            }
            kept.insert(ingredient.objectID)
            ingredient.take(line)
        }

        for ingredient in ingredients where !kept.contains(ingredient.objectID) {
            context.delete(ingredient)
        }
    }
}

extension Ingredient {

    /// Takes name, unit and amounts from `line`, assigning only what
    /// changed, so an untouched line is not sent through iCloud again.
    func take(_ line: ShoppingListLine) {
        if name != line.name { name = line.name }
        if unit != line.unit { unit = line.unit }
        if weight != line.weight { weight = line.weight }
        if normWeight != line.normWeight { normWeight = line.normWeight }
        if num != line.num { num = line.num }
        if denom != line.denom { denom = line.denom }
    }
}
