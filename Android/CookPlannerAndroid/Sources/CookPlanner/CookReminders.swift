import BakePlannerCore
import Foundation
import SwiftUI

/// Notifications for the cook mode, so the phone may lie dark on the
/// counter (the iPhone's CookReminders): one when a hands-on step begins,
/// one when a pot or oven step has run its time. They follow the live
/// plan — replaced whenever it changes, cancelled while the clock is
/// paused and when cooking ends. Delivered by WorkManager through the
/// app's own worker (Reminders.kt), so they come as banners.
@MainActor
enum CookReminders {
    private static let prefix = "cookplanner."
    /// What is scheduled now, to take back: pendingNotificationRequests()
    /// stays empty on Android.
    nonisolated(unsafe) private static var scheduled: [String] = []
    nonisolated(unsafe) private static var signature = ""
    /// The nearest reminders only; the rest follow as the plan is synced again.
    private static let limit = 20

    /// Asks once (Android 13 and later); whether reminders may be shown.
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces the reminders by those of `schedule` from `minute` on.
    /// `clockStart` is the date of the plan's minute 0: the start plus the
    /// pauses so far. Nothing happens when nothing changed.
    static func sync(schedule: KitchenSchedule, finished: [String: Int], handsDone: [String: Int], minute: Int,
                     clockStart: Date) {
        let key = schedule.placements.map { "\($0.id):\($0.start)-\($0.end)" }.joined(separator: ",")
            + "|" + finished.keys.sorted().joined(separator: ",") + "|" + handsDone.keys.sorted().joined(separator: ",")
            + "|\(Int(clockStart.timeIntervalSince1970))"
        guard key != signature else { return }
        cancel(schedule: schedule)
        signature = key

        var wanted: [(id: String, title: String, body: String, date: Date)] = []
        for placement in schedule.placements where finished[placement.id] == nil {
            let task = placement.task
            if task.handsMinutes > 0 && placement.start > minute {
                let body = task.component.isEmpty
                    ? String(localized: "Jetzt dran", bundle: .module)
                    : String(localized: "\(task.component /*%@*/) · jetzt dran", bundle: .module)
                wanted.append((prefix + "start." + task.id, task.name, body,
                               clockStart.addingTimeInterval(Double(placement.start * 60))))
            }
            if task.unattendedMinutes > 0 && placement.end > minute {
                let body = task.component.isEmpty
                    ? String(localized: "Die Zeit ist um", bundle: .module)
                    : String(localized: "\(task.component /*%@*/) · die Zeit ist um", bundle: .module)
                wanted.append((prefix + "end." + task.id, task.name, body,
                               clockStart.addingTimeInterval(Double(placement.end * 60))))
            }
        }
        let now = Date()
        for reminder in wanted.sorted(by: { $0.date < $1.date }).prefix(limit) {
            let seconds = reminder.date.timeIntervalSince(now)
            guard seconds > 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            let request = UNNotificationRequest(identifier: reminder.id, content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
            scheduled.append(reminder.id)
            Task {
                do {
                    try await UNUserNotificationCenter.current().add(request)
                } catch {
                    logger.error("could not set the reminder: \(error)")
                }
            }
        }
    }

    /// No more reminders for this plan: paused, ended, or a new run
    /// begins. Every identifier its steps can have goes, not only the ones
    /// this process set: a run taken up after the app was ended set its
    /// banners in an earlier process.
    static func cancel(schedule: KitchenSchedule) {
        signature = ""
        let all = schedule.placements.flatMap { [prefix + "start." + $0.id, prefix + "end." + $0.id] }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(Set(all + scheduled)))
        scheduled = []
    }
}
