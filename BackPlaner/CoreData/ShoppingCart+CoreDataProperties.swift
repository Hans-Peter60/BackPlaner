//
//  ShoppingCart+CoreDataProperties.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 13.01.22.
//
//

import Foundation
import CoreData


extension ShoppingCart {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ShoppingCart> {
        return NSFetchRequest<ShoppingCart>(entityName: "ShoppingCart")
    }

    @NSManaged public var id:         UUID?
    @NSManaged public var date:       Date
    @NSManaged public var ingredients:NSSet
    @NSManaged public var recipes:    NSSet
    /// Names of the cloud recipes whose ingredients are on this list, one per
    /// line. A cloud recipe has no Core Data object to relate to, so its name
    /// is kept here — otherwise the list would show ingredients with no clue
    /// where they came from.
    @NSManaged public var cloudRecipeNames: String?

    /// The cloud recipe names as a list, empty when none were added.
    public var cloudRecipeNamesArray: [String] {
        (cloudRecipeNames ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Records that a cloud recipe was put on this list, without duplicates.
    public func addCloudRecipeName(_ name: String) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }

        var names = cloudRecipeNamesArray
        guard !names.contains(cleanedName) else { return }

        names.append(cleanedName)
        cloudRecipeNames = names.joined(separator: "\n")
    }

    public var ingredientsArray: [Ingredient] {
        let set = ingredients as? Set<Ingredient> ?? []
        return set.sorted {
            $0.name < $1.name
        }
    }
}

// MARK: Generated accessors for ingredients
extension ShoppingCart {

    @objc(addIngredientsObject:)
    @NSManaged public func addToIngredients(_ value: Ingredient)

    @objc(removeIngredientsObject:)
    @NSManaged public func removeFromIngredients(_ value: Ingredient)

    @objc(addIngredients:)
    @NSManaged public func addToIngredients(_ values: NSSet)

    @objc(removeIngredients:)
    @NSManaged public func removeFromIngredients(_ values: NSSet)

}

// MARK: Generated accessors for recipes
extension ShoppingCart {

    @objc(addRecipesObject:)
    @NSManaged public func addToRecipes(_ value: Recipe)

    @objc(removeRecipesObject:)
    @NSManaged public func removeFromRecipes(_ value: Recipe)

    @objc(addRecipes:)
    @NSManaged public func addToRecipes(_ values: NSSet)

    @objc(removeRecipes:)
    @NSManaged public func removeFromRecipes(_ values: NSSet)

}

extension ShoppingCart : Identifiable {

}
