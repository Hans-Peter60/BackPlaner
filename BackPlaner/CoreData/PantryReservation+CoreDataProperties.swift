//
//  PantryReservation+CoreDataProperties.swift
//  BackPlaner
//
//  What one open plan has reserved of one pantry item. Tied to the plan by
//  its id and to the item by the item's UUID, which is the same on every
//  device; no relationships, so a plan or an item can go on its own.
//

import Foundation
import CoreData

extension PantryReservation {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PantryReservation> {
        return NSFetchRequest<PantryReservation>(entityName: "PantryReservation")
    }

    @NSManaged public var id:         UUID?
    @NSManaged public var planID:     UUID?
    @NSManaged public var recipeName: String?
    @NSManaged public var itemID:     UUID?
    @NSManaged public var amount:     Double
    /// A PantryUnit's raw value.
    @NSManaged public var unit:       String?
    @NSManaged public var planEnd:    Date?
    @NSManaged public var createdAt:  Date?

}

extension PantryReservation : Identifiable {

}
