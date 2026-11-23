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
    /// The shortest and the longest the step may take, in minutes, when the
    /// recipe gives a window; nil without one. `durationWindow` in
    /// CoreDataLogicAdapters reads and writes both as a range.
    @NSManaged public var minDuration: NSNumber?
    @NSManaged public var maxDuration: NSNumber?
    /// The oven's settings for the step: degrees Celsius, the temperature
    /// the heat falls to, steam; all nil when not set. `oven` in
    /// CoreDataLogicAdapters reads and writes them as one value.
    @NSManaged public var ovenTemperature: NSNumber?
    @NSManaged public var ovenFallingTemperature: NSNumber?
    @NSManaged public var ovenSteam: NSNumber?
    @NSManaged public var recipe:     Recipe?
    
}

extension Instruction : Identifiable {

}
