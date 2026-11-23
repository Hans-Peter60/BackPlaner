//
//  BakeActivityAttributes.swift
//  BackPlaner
//
//  The Live Activity of a running plan. The attributes name the recipe; the
//  state is the step on display and the one after it. Shared by the app,
//  which starts and updates the activity, and the widget extension, which
//  draws it. Kept apart from PlanSnapshot, which the Watch app compiles
//  too — ActivityKit does not exist there.
//

import ActivityKit
import Foundation

struct BakeActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        var instruction: String
        /// When the step is due. Also the activity's stale date while it lies
        /// ahead, so the view can switch from the countdown to "Jetzt fällig"
        /// without an update.
        var stepDate: Date
        /// Already due when the content was made. An activity whose stale
        /// date is in the past is born stale and never shown at all, so the
        /// due state has to travel as a flag instead.
        var isDue: Bool
        var followingInstruction: String?
        var followingDate: Date?
    }

    var recipeName: String
}

extension PlanSnapshot {

    /// How far ahead a step may be for a Live Activity to show it. The system
    /// ends a Live Activity after eight hours anyway, so one for a step
    /// further away would only ever show a countdown that never arrives.
    static let liveActivityHorizon: TimeInterval = 8 * 60 * 60

    /// What the Live Activity should show at `now`, or `nil` when there is
    /// nothing within reach and any running activity should end.
    func liveActivityContent(at now: Date) -> (recipeName: String, state: BakeActivityAttributes.ContentState)? {
        guard let current = currentStep(at: now),
              current.step.date.timeIntervalSince(now) < Self.liveActivityHorizon
        else { return nil }

        let following = steps.first { $0.date > current.step.date }
        let state = BakeActivityAttributes.ContentState(
            instruction: current.step.instruction,
            stepDate: current.step.date,
            isDue: current.isDue,
            // One line in the activity, so a step like "Weizensauerteig\n
            // Zutaten mischen …" must not break after its first word.
            followingInstruction: following?.instruction.replacingOccurrences(of: "\n", with: " "),
            followingDate: following?.date
        )
        return (current.step.recipeName, state)
    }
}
