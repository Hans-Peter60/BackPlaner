//
//  Item+CoreDataProperties.swift
//  BackPlaner2
//
//  Created by Hans-Peter Müller on 19.11.21.
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
