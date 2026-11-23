//
//  Recipe+CoreDataClass.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 12.02.24.
//
//

import Foundation
import CoreData

@objc(Recipe)
public class Recipe: NSManagedObject {

    /// The names of every stored recipe, for numbering a new variant
    /// ("Landbrot V3" after "Landbrot V2") — see `AdjustedRecipe.variantName`.
    static func allNames(in context: NSManagedObjectContext) -> [String] {
        let request = Recipe.fetchRequest()
        request.includesPropertyValues = true
        return ((try? context.fetch(request)) ?? []).map(\.name)
    }
}
