//
//  BakeModeText.swift
//  BakePlannerCore
//
//  What the bake mode shows and reads aloud for a planned step: the
//  ingredients of the component the step mixes, at the amount the plan was
//  made at, and the spoken text with units spelled out. The iPhone's
//  BakeModeView words it the same way; Android uses this.
//

import Foundation

public enum BakeModeText {

    /// The component the step works on, if the recipe names one for it.
    public static func component(of step: ScheduledStepData, in recipe: RecipeExportData) -> ComponentColumn? {
        ScheduledStepComponent.column(for: recipe, step: step.step, instructionText: step.instruction)
    }

    /// "• 800 g Weizenmehl 550" — one line per ingredient, at `scale` (the
    /// amount actually weighed out), units abbreviated.
    public static func ingredientLines(of component: ComponentColumn, scale: Double) -> [String] {
        component.ingredients.map { ingredient in
            "• " + Rational.getPortion(unit: ingredient.unit, weight: ingredient.weight, num: ingredient.numerator,
                                       denom: ingredient.denominator, scale: scale)
                + ingredient.name
        }
    }

    /// What is read aloud: the step, then the ingredients if there are any —
    /// as sentences rather than bullet points, units spelled out ("TL" read
    /// aloud is just letters).
    public static func spokenText(instruction: String, component: ComponentColumn?, scale: Double) -> String {
        var parts = [instruction.replacingOccurrences(of: "\n", with: ". ")]
        if let component, !component.ingredients.isEmpty {
            let heading = String(
                format: String(localized: "Zutaten für „%@“:", bundle: AppSettings.localizationBundle, locale: AppSettings.locale),
                component.name
            )
            let lines = component.ingredients.map { ingredient in
                Rational.getPortion(unit: ingredient.unit, weight: ingredient.weight, num: ingredient.numerator,
                                    denom: ingredient.denominator, scale: scale, unitStyle: .name)
                    + ingredient.name
            }
            parts.append(heading)
            parts.append(lines.joined(separator: ". "))
        }
        return parts.joined(separator: " ")
    }
}

extension ScheduledStepData {
    /// The scale the step's amounts are shown at: the one the plan was made
    /// at, or the recipe as stored for steps planned before it was recorded.
    public var effectiveServingScale: Double {
        servingScale > 0 ? servingScale : 1
    }
}
