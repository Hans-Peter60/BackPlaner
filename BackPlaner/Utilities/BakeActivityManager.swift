//
//  BakeActivityManager.swift
//  BackPlaner
//
//  Starts, updates and ends the Live Activity of the running plan. Driven by
//  the same plan snapshot as the widget, so every path that changes the plan
//  — setting reminders, shifting, marking done from a notification, a change
//  from iCloud, the app coming to the foreground — keeps the activity right.
//

import ActivityKit
import Foundation
import os

@MainActor
final class BakeActivityManager {

    static let shared = BakeActivityManager()

    /// Brings the Live Activity in line with `snapshot`: starts one for the
    /// step within reach, updates the running one, or ends it when nothing is
    /// due within the next eight hours.
    ///
    /// Starting is only possible while the app is in the foreground; from a
    /// notification action in the background the request fails quietly and
    /// the next foreground pass catches up. Updates and ends work either way.
    func refresh(with snapshot: PlanSnapshot, now: Date = Date()) {
        guard AppSettings.isLiveActivityEnabled,
              ActivityAuthorizationInfo().areActivitiesEnabled,
              let target = snapshot.liveActivityContent(at: now)
        else {
            endAll()
            return
        }

        // A stale date in the past makes the activity stale from birth, and
        // the system then never presents it. For a step already due the
        // state's `isDue` flag carries that information instead.
        let content = ActivityContent(
            state: target.state,
            staleDate: target.state.stepDate > now ? target.state.stepDate : nil,
            relevanceScore: 100
        )

        let running = Activity<BakeActivityAttributes>.activities

        if let activity = running.first(where: { $0.attributes.recipeName == target.recipeName }) {
            // One activity at a time: a second recipe's leftover goes.
            for other in running where other.id != activity.id {
                end(other)
            }
            if activity.content.state != target.state {
                Task { await activity.update(content) }
            }
            return
        }

        for other in running {
            end(other)
        }

        do {
            _ = try Activity.request(
                attributes: BakeActivityAttributes(recipeName: target.recipeName),
                content: content,
                pushType: nil
            )
            AppLog.notifications.debug("Live Activity started for \(target.recipeName)")
        } catch {
            // Expected in the background; not an error worth alarming about.
            AppLog.notifications.debug("Live Activity not started: \(error.localizedDescription)")
        }
    }

    func endAll() {
        for activity in Activity<BakeActivityAttributes>.activities {
            end(activity)
        }
    }

    private func end(_ activity: Activity<BakeActivityAttributes>) {
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
