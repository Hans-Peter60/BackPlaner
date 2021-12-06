//
//  NextSteps+CoreDataProperties.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 06.12.21.
//
//

import Foundation
import CoreData


extension NextSteps {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<NextSteps> {
        return NSFetchRequest<NextSteps>(entityName: "NextSteps")
    }

    @NSManaged public var date: Date?
    @NSManaged public var duration: Int
    @NSManaged public var id: UUID?
    @NSManaged public var instruction: String
    @NSManaged public var recipeName: String
    @NSManaged public var startTime: Int
    @NSManaged public var step: Double

}

extension NextSteps : Identifiable {

}
