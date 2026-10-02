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
    /// Groups the steps of one planning run. A recipe can be planned more
    /// than once — Saturday's and Sunday's loaf — and the plans must be told
    /// apart when one of them is shifted or deleted. `nil` on steps planned
    /// before this attribute existed; those count as one plan per recipe.
    @NSManaged public var planID:     UUID?

}

extension NextStep : Identifiable {

}
