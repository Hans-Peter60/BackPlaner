//
//  PlanChangeCheck.swift
//  BakePlannerCore
//
//  Planned steps are a snapshot of the recipe at planning time. When a
//  step's text or duration is edited afterwards, or a step is removed, the
//  plan keeps the old state until it is set again; "Geplante Schritte"
//  says so, with "Neu planen". Shared by iOS and Android so both judge a
//  plan the same way.
//

import Foundation

public enum PlanChangeCheck {

    /// A planned step as the check reads it.
    public struct PlannedStep: Equatable {
        public let step: Double
        public let instruction: String
        public let duration: Int

        public init(step: Double, instruction: String, duration: Int) {
            self.step = step
            self.instruction = instruction
            self.duration = duration
        }
    }

    /// Whether the recipe's instructions still cover its planned steps.
    /// The oven, turn-down and finish steps are generated at planning time
    /// and live only in the plan, so they do not count. A step marked done
    /// is simply missing from the plan and does not count either; a step
    /// added to the recipe afterwards is not detected.
    public static func recipeChanged(instructions: [RecipeExportInstruction], plannedSteps: [PlannedStep]) -> Bool {
        let planned = plannedSteps.filter {
            $0.step < 99
                && !BakePlanValidator.isPreheatInstruction($0.instruction)
                && !BakePlan.isTurnDownInstruction($0.instruction)
        }
        return !planned.allSatisfy { step in
            instructions.contains {
                $0.step == step.step && $0.instruction == step.instruction && $0.duration == step.duration
            }
        }
    }
}
