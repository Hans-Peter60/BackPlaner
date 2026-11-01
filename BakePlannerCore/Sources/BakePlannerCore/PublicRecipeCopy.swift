//
//  PublicRecipeCopy.swift
//  BakePlannerCore
//
//  What a public recipe becomes when the user takes it over into his own
//  recipes — directly, or by planning it. The iPhone works this out in
//  RecipeModel.uploadRecipeIntoCoreData; the rules are the same here.
//

import Foundation

public enum PublicRecipeCopy {

    /// The own copy of a public recipe, in the language it is shown in:
    /// - start times and the total duration worked out again from the steps
    ///   (Rational.calculateStartTimes), so the copy plans like the
    ///   recipe as shown;
    /// - the steps the plan adds itself ("Backofen anstellen", "Backvorgang
    ///   ist beendet") left out, the plan adds them anew;
    /// - each ingredient's weight in grams worked out again from amount and
    ///   unit, and the total weight from these.
    ///
    /// Components and steps have to be read into `recipe` before.
    public static func content(of recipe: RecipeFB, imageData: Data?) -> RecipeExportData {
        let instructions = Rational.calculateStartTimes(
            recipe.instructions,
            Date(),
            dependencies: Rational.ComponentDependency.from(recipe.components)
        )
        // What calculateStartTimes leaves in GlobalVariables.totalDuration:
        // the end of the last step. Worked out from the steps here, so a
        // second calculation running at the same time cannot change it.
        let prepTime = instructions.map { ($0.startTime ?? 0) + $0.duration }.max() ?? 0

        var content = RecipeExportData(recipeFB: recipe, imageData: imageData)
        content.prepTime = prepTime

        let generated = [GlobalVariables.startHeating, GlobalVariables.bakeEnd]
        content.instructions = instructions
            .filter { !generated.contains($0.instruction) }
            .sorted { $0.step < $1.step }
            .map { instruction in
                RecipeExportInstruction(
                    instruction: instruction.instruction,
                    step: instruction.step,
                    duration: instruction.duration,
                    startTime: instruction.startTime ?? 0,
                    bakeFlag: instruction.bakeFlag ?? false,
                    componentName: instruction.componentName
                )
            }

        let calculator = CalcIngredientWeight()
        var totalWeight = 0.0
        content.components = content.components.map { component in
            var component = component
            component.ingredients = component.ingredients.map { ingredient in
                var ingredient = ingredient
                let unit = ingredient.unit ?? ""
                if unit == "g" || unit == "Gramm" {
                    ingredient.normWeight = ingredient.weight
                } else {
                    ingredient.normWeight = calculator.calcIngredientWeight(
                        weight: ingredient.weight, unit: unit, name: ingredient.name,
                        num: ingredient.num, denom: ingredient.denom)
                }
                totalWeight += ingredient.normWeight
                return ingredient
            }
            return component
        }
        content.totalWeight = totalWeight
        return content
    }
}
