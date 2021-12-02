//
//  Recipe+CoreDataProperties.swift
//  BackPlaner2
//
//  Created by Hans-Peter Müller on 19.11.21.
//
//

import Foundation
import CoreData


extension Recipe {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Recipe> {
        return NSFetchRequest<Recipe>(entityName: "Recipe")
    }

    @NSManaged public var comments: [String]?
    @NSManaged public var featured: Bool
    @NSManaged public var id: UUID?
    @NSManaged public var image: Data
    @NSManaged public var name: String
    @NSManaged public var prepTime: Int
    @NSManaged public var servings: Int
    @NSManaged public var summary: String
    @NSManaged public var tags: [String]
    @NSManaged public var urlLink: String?
    @NSManaged public var components: NSSet
    @NSManaged public var instructions: NSSet

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
