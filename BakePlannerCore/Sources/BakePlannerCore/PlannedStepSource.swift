//
//  PlannedStepSource.swift
//  BakePlannerCore
//
//  Which recipe a planned step came from. A planned step remembers only the
//  recipe's name, and a public recipe and the user's own copy of it share
//  that name. The copy can differ from the public recipe — edited, or made
//  from an older version of it — so the wrong one would show the wrong
//  ingredients for the step, or none.
//

import Foundation

public enum PlannedStepSource: Equatable {
    case publicRecipe
    case ownRecipe

    /// One step of a recipe, as far as telling the recipes apart needs.
    public struct Step {
        public let step: Double
        public let instruction: String

        public init(step: Double, instruction: String) {
            self.step = step
            self.instruction = instruction
        }
    }

    /// The recipe the planned step `step` with the text `instruction` came
    /// from, of the public recipe and the own one of the same name (`nil`
    /// where there is none).
    ///
    /// The public recipe comes first: a plan made from it finds it. The own
    /// recipe is taken when there is no public one, or when only the own
    /// recipe has the step as planned — the user baked the copy. Steps the
    /// plan adds itself (the oven, the end) are in neither recipe and keep
    /// that order.
    public static func source(ofStep step: Double, instruction: String,
                              publicSteps: [Step]?, ownSteps: [Step]?) -> PlannedStepSource? {
        guard let publicSteps else { return ownSteps == nil ? nil : .ownRecipe }
        guard let ownSteps else { return .publicRecipe }

        func contains(_ steps: [Step]) -> Bool {
            steps.contains { $0.step == step && $0.instruction == instruction }
        }
        return !contains(publicSteps) && contains(ownSteps) ? .ownRecipe : .publicRecipe
    }
}
