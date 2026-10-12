//
//  StarterFeedingLog+CoreDataProperties.swift
//  BackPlaner
//

import Foundation
import CoreData


extension StarterFeedingLog {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<StarterFeedingLog> {
        return NSFetchRequest<StarterFeedingLog>(entityName: "StarterFeedingLog")
    }

    @NSManaged public var id:     UUID?
    @NSManaged public var date:   Date
    @NSManaged public var note:   String?
    @NSManaged public var recipe: Recipe?

    // Optional and `NSNumber`, not scalars: a peak time never measured must
    // stay apart from one of 0 minutes, and a float test never tried apart
    // from one that failed. Read and written together through `facts`
    // (StarterFeedingFacts.swift).
    @NSManaged public var peakMinutes:    NSNumber?
    @NSManaged public var floatTestPassed: NSNumber?

}

extension StarterFeedingLog : Identifiable {

}
