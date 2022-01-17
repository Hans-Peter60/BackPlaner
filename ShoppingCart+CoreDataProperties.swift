//
//  ShoppingCart+CoreDataProperties.swift
//  BackPlaner
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
