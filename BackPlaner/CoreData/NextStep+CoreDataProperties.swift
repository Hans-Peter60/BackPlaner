//
//  NextSteps+CoreDataProperties.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 12.12.21.
//
//

import Foundation
import CoreData


extension NextStep {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<NextStep> {
        return NSFetchRequest<NextStep>(entityName: "NextStep")
    }

    @NSManaged public var id:         UUID?
    @NSManaged public var step:       Double
    @NSManaged public var startTime:  Int
    @NSManaged public var recipeName: String
    @NSManaged public var instruction:String
    @NSManaged public var duration:   Int
    @NSManaged public var date:       Date

}

extension NextStep : Identifiable {

}
