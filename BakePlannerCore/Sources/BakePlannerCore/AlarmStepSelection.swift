//
//  AlarmStepSelection.swift
//  BakePlannerCore
//
//  Which scheduled steps get a real alarm beside their reminder. A
//  reminder is a notification and goes under at "stumm" or in a Focus; an
//  alarm (AlarmKit on the iPhone) rings through. The setting says whether
//  none do, the oven steps — oven on, dough into the oven, end of the bake
//  — or every step. Platform-neutral: the iPhone schedules the alarms, the
//  selection is tested here.
//

import Foundation

/// Which steps of a plan ring as an alarm.
public enum AlarmStepScope: String, CaseIterable, Sendable {
    /// Reminders only.
    case off
    /// Oven on, dough into the oven, end of the bake.
    case oven
    /// Every step of every plan.
    case all
}

extension AppSettingsKeys {
    public static let alarmSteps = "settings.alarmSteps"
}

extension AppSettings {
    public static let defaultAlarmScope = AlarmStepScope.off

    public static var storedAlarmScope: AlarmStepScope {
        UserDefaults.standard.string(forKey: AppSettingsKeys.alarmSteps)
            .flatMap(AlarmStepScope.init(rawValue:)) ?? defaultAlarmScope
    }
}

public enum AlarmStepSelection {

    /// The step number of a plan's end step ("Fertig" / "Backende").
    public static let endStepNumber = 99.0

    /// The steps among `steps` that ring under `scope`, those still ahead
    /// of `now` only: an alarm whose time has passed is never set again.
    /// For `.oven`, a plan that never bakes — feeding a starter — gets no
    /// alarm at all; its end would ring for nothing.
    public static func steps(for scope: AlarmStepScope, in steps: [ScheduledStepData], now: Date) -> [ScheduledStepData] {
        let ahead = steps.filter { $0.date > now }
        switch scope {
        case .off:
            return []
        case .all:
            return ahead
        case .oven:
            let bakingPlans = Set(steps.compactMap { step -> String? in
                BakePlanValidator.isBakingStartInstruction(step.instruction) ? planKey(of: step) : nil
            })
            return ahead.filter { step in
                bakingPlans.contains(planKey(of: step)) && isOvenStep(step)
            }
        }
    }

    /// Oven on (the recipe's own preheating step or the generated one),
    /// the dough going in, and the end of the plan.
    public static func isOvenStep(_ step: ScheduledStepData) -> Bool {
        step.step == endStepNumber
            || BakePlanValidator.isBakingStartInstruction(step.instruction)
            || BakePlanValidator.isPreheatInstruction(step.instruction)
    }

    /// Steps of one plan: by the plan id, or by the recipe name for steps
    /// planned before plans had an id.
    private static func planKey(of step: ScheduledStepData) -> String {
        step.planID?.uuidString ?? "recipe:\(step.recipeName)"
    }
}
