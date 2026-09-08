//
//  Instruction+CoreDataProperties.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 12.12.21.
//
//

import Foundation
import CoreData


extension Instruction {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Instruction> {
        return NSFetchRequest<Instruction>(entityName: "Instruction")
    }

    @NSManaged public var id:         UUID?
    @NSManaged public var step:       Double
    @NSManaged public var startTime:  Int
    @NSManaged public var instruction:String
    @NSManaged public var duration:   Int
    @NSManaged public var date:       Date?
    @NSManaged public var bakeFlag:   Bool
    /// The component this step prepares, for steps the recipe import generates
    /// per component. The bake plan schedules those in dependency order, and
    /// reads the dependency from here instead of from the step's wording.
    @NSManaged public var componentName: String?
    @NSManaged public var recipe:     Recipe?
    
}

extension Instruction : Identifiable {

}
