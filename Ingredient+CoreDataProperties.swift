//
//  Ingredient+CoreDataProperties.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 12.12.21.
//
//

import Foundation
import CoreData


extension Ingredient {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Ingredient> {
        return NSFetchRequest<Ingredient>(entityName: "Ingredient")
    }

    @NSManaged public var id:           UUID?
    @NSManaged public var number:       Int
    @NSManaged public var weight:       Double
    @NSManaged public var normWeight:   Double
    @NSManaged public var unit:         String?
    @NSManaged public var num:          Int
    @NSManaged public var name:         String
    @NSManaged public var denom:        Int
    @NSManaged public var component:    Component?
    @NSManaged public var shoppingCarts:NSSet?

}

// MARK: Generated accessors for shoppingCart
extension Ingredient {

    @objc(addShoppingCartsObject:)
    @NSManaged public func addToShoppingCarts(_ value: ShoppingCart)

    @objc(removeShoppingCartsObject:)
    @NSManaged public func removeFromShoppingCarts(_ value: ShoppingCart)

    @objc(addShoppingCarts:)
    @NSManaged public func addToShoppingCarts(_ values: NSSet)

    @objc(removeShoppingCarts:)
    @NSManaged public func removeFromShoppingCarts(_ values: NSSet)

}

extension Ingredient : Identifiable {

}
