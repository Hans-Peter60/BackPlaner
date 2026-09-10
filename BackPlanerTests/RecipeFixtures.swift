//
//  RecipeFixtures.swift
//  BackPlanerTests
//
//  Recipe objects for the translation tests. The texts are deliberately whole
//  sentences: the language detector needs prose to judge by, and a recipe made
//  of nothing but ingredient names is a separate case the tests state outright.
//

import Foundation
@testable import BackPlaner

enum RecipeFixtures {

    static func recipe(name: String,
                       summary: String,
                       steps: [String],
                       component: String,
                       ingredients: [String]) -> RecipeFB {
        let recipe = RecipeFB()
        recipe.name = name
        recipe.summary = summary

        let mainComponent = ComponentFB()
        mainComponent.name = component
        mainComponent.ingredients = ingredients.map { ingredientName in
            let ingredient = IngredientFB()
            ingredient.name = ingredientName
            return ingredient
        }
        recipe.components = [mainComponent]

        recipe.instructions = steps.map { step in
            let instruction = InstructionFB()
            instruction.instruction = step
            return instruction
        }

        return recipe
    }

    static func german() -> RecipeFB {
        recipe(name: "Landbrot",
               summary: "Ein kräftiges Mischbrot mit Sauerteig und langer Teigführung.",
               steps: ["Alle Zutaten zu einem Teig verkneten und dreißig Minuten ruhen lassen.",
                       "Den Teig über Nacht im Kühlschrank reifen lassen.",
                       "Am Morgen bei 250 Grad mit Dampf backen."],
               component: "Hauptteig",
               ingredients: ["Weizenmehl", "Wasser", "Salz", "Sauerteig"])
    }

    static func french() -> RecipeFB {
        recipe(name: "Pain de campagne",
               summary: "Un pain rustique au levain naturel et à longue fermentation.",
               steps: ["Mélanger tous les ingrédients et laisser reposer trente minutes.",
                       "Laisser la pâte maturer toute la nuit au réfrigérateur.",
                       "Cuire le matin à 250 degrés avec de la vapeur."],
               component: "Pâte principale",
               ingredients: ["Farine de blé", "Eau", "Sel", "Levain"])
    }

    static func english() -> RecipeFB {
        recipe(name: "Country loaf",
               summary: "A hearty sourdough loaf with a long and slow fermentation.",
               steps: ["Knead all the ingredients into a dough and let it rest for thirty minutes.",
                       "Leave the dough to mature in the fridge overnight.",
                       "Bake it in the morning at 250 degrees with steam."],
               component: "Main dough",
               ingredients: ["Wheat flour", "Water", "Salt", "Sourdough starter"])
    }

    /// Overwrites a recipe's live text with another recipe's, the way displaying
    /// a translation does. The cache is left untouched, so this builds the state
    /// "filed under one language, currently showing another".
    static func replaceLiveText(of recipe: RecipeFB, with other: RecipeFB) {
        recipe.name = other.name
        recipe.summary = other.summary

        for (index, instruction) in other.instructions.enumerated()
        where recipe.instructions.indices.contains(index) {
            recipe.instructions[index].instruction = instruction.instruction
        }

        for (index, component) in other.components.enumerated()
        where recipe.components.indices.contains(index) {
            recipe.components[index].name = component.name
            for (ingredientIndex, ingredient) in component.ingredients.enumerated()
            where recipe.components[index].ingredients.indices.contains(ingredientIndex) {
                recipe.components[index].ingredients[ingredientIndex].name = ingredient.name
            }
        }
    }
}
