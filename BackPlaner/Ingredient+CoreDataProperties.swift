//
//  Ingredient+CoreDataProperties.swift
//  BackPlaner2
//
//  Created by Hans-Peter Müller on 19.11.21.
//
//

import Foundation
import CoreData


extension Ingredient {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Ingredient> {
        return NSFetchRequest<Ingredient>(entityName: "Ingredient")
    }

    @NSManaged public var denom: Int
    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var num: Int
    @NSManaged public var unit: String?
    @NSManaged public var weight: Double
    @NSManaged public var component: Component?

}

extension Ingredient : Identifiable {

}
