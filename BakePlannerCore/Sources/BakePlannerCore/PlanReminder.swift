//
//  PlanReminder.swift
//  BakePlannerCore
//
//  What a reminder of a planned step says: "Backhinweis" over the step's
//  instruction and, for a step of the recipe, the ingredients of its
//  component at the amount planned — as the iPhone has always worded it,
//  now shared with Android.
//

import Foundation

public enum PlanReminder {

    /// The reminder's title, in the app's language.
    public static var title: String {
        String(localized: "Backhinweis", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
    }

    /// The instruction, and below it the ingredients when there are any.
    public static func body(instruction: String, details: String?) -> String {
        guard let details, !details.isEmpty else { return instruction }
        return instruction + "\n\n" + details
    }

    /// The ingredients of the component a scheduled step works on, at
    /// `scale` — nil for a step the plan generated (oven, end) or one that
    /// names no component.
    public static func details(of step: ScheduledStepData, in recipe: RecipeExportData) -> String? {
        guard let instruction = recipe.instructions.first(where: {
            $0.step == step.step && $0.instruction == step.instruction
        }) else { return nil }
        return ScheduledStepComponent.column(for: recipe, storedComponentName: instruction.componentName,
                                             instructionText: instruction.instruction)
            .flatMap { ScheduledStepComponent.ingredientsText(for: $0, scale: step.servingScale) }
    }

    /// The identifier of a step's reminder, from the step's id.
    public static func identifier(of step: ScheduledStepData) -> String? {
        step.id.map { "bakeplanner-step-" + $0.uuidString }
    }
}
