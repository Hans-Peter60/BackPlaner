//
//  RecipeEditing.swift
//  BakePlannerCore
//
//  What an editor needs that is arithmetic: reading the amount a user
//  types — "250", "1,5", "1/4", "1 1/2" — and working out a recipe's
//  weights and step times again after it was edited, the way the iOS app
//  does after editing (Recipe.recalculateTotalWeight, the start times of
//  EditRecipeView).
//

import Foundation

/// An ingredient's amount as typed: a weight, or a fraction of a unit.
public struct IngredientAmountText: Equatable {
    public var weight: Double
    public var numerator: Int
    public var denominator: Int

    public init(weight: Double, numerator: Int, denominator: Int) {
        self.weight = weight
        self.numerator = numerator
        self.denominator = denominator
    }

    /// The amount `text` stands for: a decimal number (comma or point)
    /// becomes the weight, a fraction ("1/4", "1 1/2") the numerator and
    /// denominator. Empty text is no amount; anything else is `nil`.
    public static func parse(_ text: String) -> IngredientAmountText? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return IngredientAmountText(weight: 0, numerator: 0, denominator: 0) }

        if trimmed.contains("/") {
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard (1...2).contains(parts.count) else { return nil }
            let fraction = parts[parts.count - 1].split(separator: "/")
            guard fraction.count == 2,
                  let numerator = Int(fraction[0]), let denominator = Int(fraction[1]),
                  numerator >= 0, denominator > 0 else { return nil }
            var whole = 0
            if parts.count == 2 {
                guard let value = Int(parts[0]), value >= 0 else { return nil }
                whole = value
            }
            return IngredientAmountText(weight: 0, numerator: whole * denominator + numerator, denominator: denominator)
        }

        guard let weight = Double(trimmed.replacingOccurrences(of: ",", with: ".")), weight >= 0 else { return nil }
        return IngredientAmountText(weight: weight, numerator: 0, denominator: 0)
    }

    /// The amount as the editor shows it: "250", "1,5", "1/4", "1 1/2";
    /// empty for none. Decimals use `decimalSeparator`.
    public static func text(weight: Double, numerator: Int, denominator: Int,
                            decimalSeparator: String = AppSettings.locale.decimalSeparator ?? ",") -> String {
        if numerator > 0, denominator > 0 {
            let whole = numerator / denominator
            let rest = numerator % denominator
            // A whole number of units stays a fraction ("1/1" is a whole
            // component), so reading the text back gives the same amount.
            if rest == 0 { return "\(numerator)/\(denominator)" }
            return whole > 0 ? "\(whole) \(rest)/\(denominator)" : "\(rest)/\(denominator)"
        }
        guard weight > 0 else { return "" }
        if weight == weight.rounded() { return String(Int(weight)) }
        return String(weight).replacingOccurrences(of: ".", with: decimalSeparator)
    }
}

extension RecipeExportData {
    /// The recipe with every instruction that describes repeated
    /// stretch-and-folds ("nach 30 und 60 Minuten dehnen und falten")
    /// resolved into one sub-step per fold, as the iOS forms do when a step
    /// is saved by hand (TimedFoldExpansion). The steps come back in the
    /// order of their numbers. Nothing to resolve leaves the recipe as it is.
    public func expandingTimedFolds() -> RecipeExportData {
        let instructionsFB = instructions.map { instruction -> InstructionFB in
            let instructionFB = InstructionFB()
            instructionFB.instruction = instruction.instruction
            instructionFB.step = instruction.step
            instructionFB.duration = instruction.duration
            instructionFB.startTime = instruction.startTime
            instructionFB.bakeFlag = instruction.bakeFlag
            instructionFB.componentName = instruction.componentName
            instructionFB.minDuration = instruction.minDuration
            instructionFB.maxDuration = instruction.maxDuration
            instructionFB.oven = instruction.oven
            return instructionFB
        }
        var expanded = instructionsFB
        guard TimedFoldExpansion.expand(&expanded) else { return self }
        var recipe = self
        recipe.instructions = expanded
            .sorted { $0.step < $1.step }
            .map { instructionFB in
                RecipeExportInstruction(instruction: instructionFB.instruction, step: instructionFB.step,
                                        duration: instructionFB.duration, startTime: instructionFB.startTime ?? 0,
                                        bakeFlag: instructionFB.bakeFlag ?? false,
                                        componentName: instructionFB.componentName,
                                        minDuration: instructionFB.durationWindow?.lowerBound,
                                        maxDuration: instructionFB.durationWindow?.upperBound,
                                        oven: instructionFB.oven)
            }
        return recipe
    }

    /// The recipe with its derived values worked out again after an edit:
    /// each ingredient's weight in grams (`normWeight`), the total weight,
    /// every step's start and the preparation time — the same rules the iOS
    /// app applies after editing a recipe.
    public func recalculated() -> RecipeExportData {
        var recipe = self
        let calculator = CalcIngredientWeight()
        recipe.totalWeight = 0
        for c in recipe.components.indices {
            for i in recipe.components[c].ingredients.indices {
                let ingredient = recipe.components[c].ingredients[i]
                let grams = calculator.calcIngredientWeight(weight: ingredient.weight, unit: ingredient.unit ?? "",
                                                            name: ingredient.name, num: ingredient.num,
                                                            denom: ingredient.denom)
                recipe.components[c].ingredients[i].normWeight = grams
                recipe.totalWeight += grams
            }
        }

        let componentsFB = recipe.components.map { component -> ComponentFB in
            let componentFB = ComponentFB()
            componentFB.name = component.name
            componentFB.ingredients = component.ingredients.map { ingredient in
                let ingredientFB = IngredientFB()
                ingredientFB.name = ingredient.name
                ingredientFB.weight = ingredient.weight
                return ingredientFB
            }
            return componentFB
        }
        let instructionsFB = recipe.instructions.map { instruction -> InstructionFB in
            let instructionFB = InstructionFB()
            instructionFB.instruction = instruction.instruction
            instructionFB.step = instruction.step
            instructionFB.duration = instruction.duration
            instructionFB.startTime = instruction.startTime
            instructionFB.componentName = instruction.componentName
            return instructionFB
        }
        let timed = Rational.calculateStartTimes(instructionsFB, Date(),
                                                 dependencies: Rational.ComponentDependency.from(componentsFB))
        for (index, instruction) in timed.enumerated() {
            recipe.instructions[index].startTime = instruction.startTime ?? 0
        }
        // The end of the last step — what calculateStartTimes also leaves in
        // GlobalVariables.totalDuration. Worked out from the steps here, so
        // a second calculation running at the same time (another test, the
        // widget) cannot change it.
        recipe.prepTime = timed.map { ($0.startTime ?? 0) + $0.duration }.max() ?? 0
        return recipe
    }
}
