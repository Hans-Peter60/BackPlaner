//
//  Item+CoreDataProperties.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 12.02.24.
//
//

import Foundation
import CoreData


extension Item {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Item> {
        return NSFetchRequest<Item>(entityName: "Item")
    }

    @NSManaged public var timestamp: Date?

}

extension Item : Identifiable {

}
