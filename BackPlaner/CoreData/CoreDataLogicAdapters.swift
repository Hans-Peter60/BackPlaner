//
//  CoreDataLogicAdapters.swift
//  BackPlaner
//
//  The bridge from the Core Data objects of an own recipe to the plain
//  structs the calculation logic works on. Keeping it here leaves
//  DoughComposition and Rational free of Core Data, so they can later move
//  into a platform-neutral package unchanged.
//

import Foundation
import CoreData

extension DoughComposition {
    static func components(of recipe: Recipe) -> [Component] {
        recipe.componentsArray.map { component in
            Component(name: component.name, ingredients: component.ingredientsArray.map { ingredient in
                Ingredient(name: ingredient.name,
                           grams: ingredient.normWeight > 0 ? ingredient.normWeight : ingredient.weight,
                           weight: ingredient.weight,
                           numerator: ingredient.num,
                           denominator: ingredient.denom)
            })
        }
    }
}

extension Rational.ComponentDependency {
    static func from(_ components: [Component]) -> [Rational.ComponentDependency] {
        let names = components.map { $0.name }
        return components.map { component in
            Rational.ComponentDependency(
                name: component.name,
                requires: requirements(
                    of: component.ingredientsArray.filter { $0.weight == 0 }.map { $0.name },
                    componentNames: names,
                    excluding: component.name
                )
            )
        }
    }
}
