//
//  BakeHistory+CoreDataProperties.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 12.12.21.
//
//

import Foundation
import CoreData


extension BakeHistory {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<BakeHistory> {
        return NSFetchRequest<BakeHistory>(entityName: "BakeHistory")
    }

    @NSManaged public var id:     UUID?
    @NSManaged public var images: [Data]?
    @NSManaged public var date:   Date
    @NSManaged public var comment:String
    @NSManaged public var recipe: Recipe?

    // What the bake was like, for the next bake of the same recipe. All
    // optional and `NSNumber`, not scalars: a temperature that was never
    // measured must stay apart from one of 0 °C. Read and written together
    // through `facts` (BakeHistoryFacts.swift).
    @NSManaged public var roomTemperature:   NSNumber?
    @NSManaged public var doughTemperature:  NSNumber?
    @NSManaged public var bulkProofMinutes:  NSNumber?
    @NSManaged public var finalProofMinutes: NSNumber?
    @NSManaged public var flour:   String?
    @NSManaged public var outcome: String?

}

extension BakeHistory : Identifiable {

}
