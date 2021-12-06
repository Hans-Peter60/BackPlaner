//
//  Instruction+CoreDataProperties.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 06.12.21.
//
//

import Foundation
import CoreData


extension Instruction {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Instruction> {
        return NSFetchRequest<Instruction>(entityName: "Instruction")
    }

    @NSManaged public var date: Date?
    @NSManaged public var duration: Int
    @NSManaged public var id: UUID?
    @NSManaged public var instruction: String
    @NSManaged public var startTime: Int
    @NSManaged public var step: Double
    @NSManaged public var recipe: Recipe?

}

extension Instruction : Identifiable {

}
