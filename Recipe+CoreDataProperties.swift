//
//  Recipe+CoreDataProperties.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 12.12.21.
//
//

import Foundation
import CoreData


extension Recipe {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Recipe> {
        return NSFetchRequest<Recipe>(entityName: "Recipe")
    }

    @NSManaged public var id:             UUID?
    @NSManaged public var urlLink:        String?
    @NSManaged public var tags:           [String]
    @NSManaged public var summary:        String
    @NSManaged public var prepTime:       Int
    @NSManaged public var totalWeight:    Double
    @NSManaged public var name:           String
    @NSManaged public var image:          Data
    @NSManaged public var firestoreId:    String?
    @NSManaged public var bakeHistoryFlag:Bool
    @NSManaged public var rating:         Int
    @NSManaged public var components:     NSSet
    @NSManaged public var bakeHistories:  NSSet
    @NSManaged public var instructions:   NSSet

    public var componentsArray: [Component] {
        let set = components as? Set<Component> ?? []
        return set.sorted {
            $0.number < $1.number
        }
    }

    public var instructionsArray: [Instruction] {
        let set = instructions as? Set<Instruction> ?? []
        return set.sorted {
            $0.step < $1.step
        }
    }
    
    public var bakeHistoriesArray: [BakeHistory] {
        let set = bakeHistories as? Set<BakeHistory> ?? []
        return set.sorted {
            $0.date > $1.date
        }
    }
}

// MARK: Generated accessors for bakeHistories
extension Recipe {

    @objc(addBakeHistoriesObject:)
    @NSManaged public func addToBakeHistories(_ value: BakeHistory)

    @objc(removeBakeHistoriesObject:)
    @NSManaged public func removeFromBakeHistories(_ value: BakeHistory)

    @objc(addBakeHistories:)
    @NSManaged public func addToBakeHistories(_ values: NSSet)

    @objc(removeBakeHistories:)
    @NSManaged public func removeFromBakeHistories(_ values: NSSet)

}

// MARK: Generated accessors for components
extension Recipe {

    @objc(addComponentsObject:)
    @NSManaged public func addToComponents(_ value: Component)

    @objc(removeComponentsObject:)
    @NSManaged public func removeFromComponents(_ value: Component)

    @objc(addComponents:)
    @NSManaged public func addToComponents(_ values: NSSet)

    @objc(removeComponents:)
    @NSManaged public func removeFromComponents(_ values: NSSet)

}

// MARK: Generated accessors for instructions
extension Recipe {

    @objc(addInstructionsObject:)
    @NSManaged public func addToInstructions(_ value: Instruction)

    @objc(removeInstructionsObject:)
    @NSManaged public func removeFromInstructions(_ value: Instruction)

    @objc(addInstructions:)
    @NSManaged public func addToInstructions(_ values: NSSet)

    @objc(removeInstructions:)
    @NSManaged public func removeFromInstructions(_ values: NSSet)

}

extension Recipe : Identifiable {

}
