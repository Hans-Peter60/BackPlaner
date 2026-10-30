//
//  CurrentStepRule.swift
//  BakePlannerProbe — copy of BackPlaner/Utilities/CurrentStepRule.swift
//
//  Which planned step matters right now — the one rule behind the main menu
//  card, the bake mode, Siri and the widget. Compiled into both the app and
//  the widget extension.
//

import Foundation

enum CurrentStepRule {

    /// How long a step counts as "due now" after its time has come. A step
    /// that is not marked done stays in the plan, so without this an old,
    /// finished plan would keep its last step on display forever.
    static let dueGracePeriod: TimeInterval = 60 * 60

    /// The step that matters at `now`, and whether its time has already come.
    /// `steps` are sorted by date, earliest first.
    ///
    /// A step that became due within the grace period and is not marked done
    /// yet comes first — when the reminder fires, that is the thing to do,
    /// not the one after it. Otherwise the earliest step still ahead. A newer
    /// due step always supersedes an older one.
    static func currentStep<Step>(in steps: [Step], at now: Date,
                                  date: (Step) -> Date) -> (step: Step, isDue: Bool)? {
        if let due = steps.last(where: { date($0) <= now }),
           now.timeIntervalSince(date(due)) < dueGracePeriod {
            return (due, true)
        }
        if let upcoming = steps.first(where: { date($0) > now }) {
            return (upcoming, false)
        }
        return nil
    }
}
