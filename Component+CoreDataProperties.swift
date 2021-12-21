//
//  Component+CoreDataProperties.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 12.12.21.
//
//

import Foundation
import CoreData


extension Component {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Component> {
        return NSFetchRequest<Component>(entityName: "Component")
    }

    @NSManaged public var name: String
    @NSManaged public var number: Int
    @NSManaged public var id: UUID?
    @NSManaged public var recipe: Recipe?
    @NSManaged public var ingredients: NSSet

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

extension Component : Identifiable {

}
