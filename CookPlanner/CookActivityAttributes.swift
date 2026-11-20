//
//  CookActivityAttributes.swift
//  CookPlanner
//
//  The Live Activity of a dish being cooked: what the lock screen and the
//  Dynamic Island show while the phone lies on the counter. Shared by the
//  app, which starts and updates the activity, and the widget extension,
//  which draws it — so this file belongs to both targets and uses nothing
//  but Foundation.
//

import ActivityKit
import Foundation

struct CookActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        /// When the dish is done by the live plan; the countdown runs to it.
        var finishDate: Date
        /// The hands-on step in progress, if any.
        var currentStep: String?
        var currentComponent: String?
        /// The next hands-on step and when it begins; the activity's stale
        /// date, so the view can switch to "Jetzt dran" without an update.
        var nextStep: String?
        var nextDate: Date?
        /// Pots and oven steps running on their own right now.
        var runningCount: Int
        var doneCount: Int
        var totalCount: Int
        /// The clock stands; `pausedRemainingMinutes` is what is left.
        var isPaused: Bool
        var pausedRemainingMinutes: Int
    }

    var dishName: String
}
