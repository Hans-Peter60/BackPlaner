//
//  PantryItem+CoreDataProperties.swift
//  BackPlaner
//
//  One thing in the pantry: a bag of flour, a packet of yeast. No
//  relationship to a recipe — the match to a recipe's ingredients is made
//  by name when it is needed (PantryStore.item(matching:)).
//

import Foundation
import CoreData

extension PantryItem {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PantryItem> {
        return NSFetchRequest<PantryItem>(entityName: "PantryItem")
    }

    @NSManaged public var id:         UUID?
    @NSManaged public var name:       String?
    @NSManaged public var amount:     Double
    /// A PantryUnit's raw value: "g", "kg" or "St".
    @NSManaged public var unit:       String?
    @NSManaged public var bestBefore: Date?
    @NSManaged public var openedOn:   Date?
    @NSManaged public var note:       String?
    @NSManaged public var updatedAt:  Date?

}

extension PantryItem : Identifiable {

}
