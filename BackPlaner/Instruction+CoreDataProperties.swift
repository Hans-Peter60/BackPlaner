//
//  Instruction+CoreDataProperties.swift
//  BackPlaner2
//
//  Created by Hans-Peter Müller on 22.11.21.
//
//

import Foundation
import CoreData


extension Instruction {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Instruction> {
        return NSFetchRequest<Instruction>(entityName: "Instruction")
    }

    @NSManaged public var duration: Int
    @NSManaged public var id: UUID?
    @NSManaged public var instruction: String
    @NSManaged public var step: Double
    @NSManaged public var startTime: Int
    @NSManaged public var date: Date?
    @NSManaged public var recipe: Recipe?

}

extension Instruction : Identifiable {

}
