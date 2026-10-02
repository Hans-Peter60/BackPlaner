//
//  ScheduledStepComponent.swift
//  BackPlaner
//

import Foundation

/// Which component a planned step mixes, and the ingredient list that goes
/// with it.
///
/// Shared by the list of planned steps (the "i" button) and by the reminders,
/// which carry the same list in their text so it can be read off the lock
/// screen while weighing out.
enum ScheduledStepComponent {

    // MARK: Finding the component

    /// Which component a step mixes.
    ///
    /// The stored `componentName` wins when the instruction has one; only the
    /// recipe import fills it in. Recipes typed in by hand have none, so their
    /// steps are matched by wording instead: "Vorteig A herstellen" names the
    /// component it prepares. When several component names occur in the text,
    /// the one mentioned first wins, and among names starting at the same spot
    /// the longer one — so "Vorteig A" beats "Vorteig".
    static func componentName(
        stored: String?,
        instructionText: String,
        among componentNames: [String]
    ) -> String? {
        if let stored, componentNames.contains(stored) {
            return stored
        }

        let text = instructionText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        var bestName: String?
        var bestPosition = text.endIndex
        var bestLength = 0

        for name in componentNames {
            let needle = name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !needle.isEmpty, let range = text.range(of: needle) else { continue }

            let isEarlier = range.lowerBound < bestPosition
            let isLongerAtSameSpot = range.lowerBound == bestPosition && needle.count > bestLength
            if isEarlier || isLongerAtSameSpot {
                bestName = name
                bestPosition = range.lowerBound
                bestLength = needle.count
            }
        }

        return bestName
    }

    /// The component one of the user's own recipes mixes in the given step.
    ///
    /// `step` is the step number a planned step remembers; it leads back to
    /// the instruction and its stored component name. `instructionText` is the
    /// wording to fall back on.
    static func column(for recipe: Recipe, step: Double?, instructionText: String) -> ComponentColumn? {
        let instruction = recipe.instructionsArray.first { $0.step == step }
        return column(for: recipe, instruction: instruction, instructionText: instructionText)
    }

    /// The component one of the user's own recipes mixes in `instruction`.
    static func column(for recipe: Recipe, instruction: Instruction?, instructionText: String) -> ComponentColumn? {
        let components = recipe.componentsArray
        guard let name = componentName(
            stored: instruction?.componentName,
            instructionText: instructionText,
            among: components.map(\.name)
        ), let component = components.first(where: { $0.name == name }) else { return nil }
        return ComponentColumn.columns(of: [component]).first
    }

    /// The component a public recipe mixes in the given step.
    static func column(for recipe: RecipeFB, step: Double?, instructionText: String) -> ComponentColumn? {
        let instruction = recipe.instructions.first { $0.step == step }
        return column(for: recipe, instruction: instruction, instructionText: instructionText)
    }

    /// The component a public recipe mixes in `instruction`.
    static func column(for recipe: RecipeFB, instruction: InstructionFB?, instructionText: String) -> ComponentColumn? {
        guard let name = componentName(
            stored: instruction?.componentName,
            instructionText: instructionText,
            among: recipe.components.map(\.name)
        ), let component = recipe.components.first(where: { $0.name == name }) else { return nil }
        return ComponentColumn.columns(of: [component]).first
    }

    // MARK: Reminder text

    /// The ingredient list as it goes into a reminder, headed by the
    /// component's name — or `nil` when the component has no ingredients, so a
    /// reminder never ends in an empty heading.
    ///
    /// Uses the in-app language, like every other reminder text, since the
    /// notification is composed outside SwiftUI.
    static func ingredientsText(for component: ComponentColumn, scale: Double) -> String? {
        guard !component.ingredients.isEmpty else { return nil }

        let heading = String(
            format: String(localized: "Zutaten für „%@“:", bundle: AppSettings.localizationBundle, locale: AppSettings.locale),
            component.name
        )
        let lines = component.ingredients.map { ingredient in
            "• " + Rational.getPortion(unit: ingredient.unit,
                                       weight: ingredient.weight,
                                       num: ingredient.numerator,
                                       denom: ingredient.denominator,
                                       scale: scale)
                + ingredient.name
        }
        return ([heading] + lines).joined(separator: "\n")
    }
}
