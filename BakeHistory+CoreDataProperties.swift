//
//  BakeHistory+CoreDataProperties.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 06.12.21.
//
//

import Foundation
import CoreData


extension BakeHistory {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<BakeHistory> {
        return NSFetchRequest<BakeHistory>(entityName: "BakeHistory")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var date: Date?
    @NSManaged public var comment: String
    @NSManaged public var images: [Data]
    @NSManaged public var recipe: Recipe?

}

extension BakeHistory : Identifiable {

}
