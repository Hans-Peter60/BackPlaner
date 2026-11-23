//
//  CookActivityManager.swift
//  CookPlanner
//
//  Starts, updates and ends the Live Activity of the dish being cooked.
//  Fed by the cook mode at every change of the live plan; the activity's
//  stale date is the next step's start, so the lock screen turns to
//  "Jetzt dran" on its own while the app is not running.
//

import ActivityKit
import Foundation

@MainActor
final class CookActivityManager {

    static let shared = CookActivityManager()

    /// Brings the activity in line with `state`: starts one, updates the
    /// running one when something changed. Starting needs the app in front.
    func refresh(dishName: String, state: CookActivityAttributes.ContentState, now: Date = Date()) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let staleDate = state.nextDate.flatMap { $0 > now && !state.isPaused ? $0 : nil }
        let content = ActivityContent(state: state, staleDate: staleDate, relevanceScore: 100)
        let running = Activity<CookActivityAttributes>.activities
        if let activity = running.first(where: { $0.attributes.dishName == dishName }) {
            for other in running where other.id != activity.id { end(other) }
            if activity.content.state != state {
                Task { await activity.update(content) }
            }
            return
        }
        for other in running { end(other) }
        _ = try? Activity.request(attributes: CookActivityAttributes(dishName: dishName), content: content, pushType: nil)
    }

    func endAll() {
        for activity in Activity<CookActivityAttributes>.activities { end(activity) }
    }

    private func end(_ activity: Activity<CookActivityAttributes>) {
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
