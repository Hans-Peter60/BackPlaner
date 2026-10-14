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
    /// Whether this step was queued by `RecurringBakePlanner` rather than by
    /// the user tapping "Erinnerungen setzen". `false` on steps planned
    /// before this attribute existed.
    @NSManaged public var isAutomaticRecurrence: Bool
    /// The serving scale the plan was made at (1.0 is the recipe as
    /// stored), so the ingredient lists of the plan show the amounts that
    /// were actually weighed out — the reminders already carry them. `0`
    /// on steps planned before this attribute existed; see
    /// `effectiveServingScale`.
    @NSManaged public var servingScale: Double

    /// The stored scale, or 1 for a step from before it was recorded.
    var effectiveServingScale: Double {
        servingScale > 0 ? servingScale : 1
    }

}

extension NextStep : Identifiable {

}
