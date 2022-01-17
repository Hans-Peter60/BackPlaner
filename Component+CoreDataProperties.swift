//
//  Component+CoreDataProperties.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 13.01.22.
//
//

import Foundation
import CoreData


extension Component {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Component> {
        return NSFetchRequest<Component>(entityName: "Component")
    }

    @NSManaged public var id:          UUID?
    @NSManaged public var name:        String
    @NSManaged public var number:      Int
    @NSManaged public var ingredients: NSSet?
    @NSManaged public var recipe:      Recipe?

    public var ingredientsArray: [Ingredient] {
        let set = ingredients as? Set<Ingredient> ?? []
        return set.sorted {
            $0.number < $1.number
        }
    }
}

// MARK: Generated accessors for ingredients
extension Component {

    @objc(addIngredientsObject:)
    @NSManaged public func addToIngredients(_ value: Ingredient)

    @objc(removeIngredientsObject:)
    @NSManaged public func removeFromIngredients(_ value: Ingredient)

    @objc(addIngredients:)
    @NSManaged public func addToIngredients(_ values: NSSet)

    @objc(removeIngredients:)
    @NSManaged public func removeFromIngredients(_ values: NSSet)

}

// MARK: Generated accessors for shoppingCart
extension Component {

    @objc(addShoppingCartObject:)
    @NSManaged public func addToShoppingCart(_ value: ShoppingCart)

    @objc(removeShoppingCartObject:)
    @NSManaged public func removeFromShoppingCart(_ value: ShoppingCart)

    @objc(addShoppingCart:)
    @NSManaged public func addToShoppingCart(_ values: NSSet)

    @objc(removeShoppingCart:)
    @NSManaged public func removeFromShoppingCart(_ values: NSSet)

}

extension Component : Identifiable {

}
