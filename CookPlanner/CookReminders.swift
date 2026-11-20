//
//  CookReminders.swift
//  CookPlanner
//
//  Local notifications for the cook mode, so the cook may lock the phone
//  and still hear when a step is due: one when a hands-on step begins, one
//  when a pot or oven step has run its time. They follow the live plan —
//  rescheduled whenever it changes, cancelled while the clock is paused
//  and when cooking ends.
//

import BakePlannerCore
import Foundation
import UserNotifications

@MainActor
final class CookReminders: NSObject, UNUserNotificationCenterDelegate {

    static let shared = CookReminders()

    private static let prefix = "cook."

    /// Asks once; answers whether reminders may be shown.
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    /// Replaces the pending reminders by those of `schedule` from `minute`
    /// on. `clockStart` is the wall-clock date of the plan's minute 0, the
    /// start plus the pauses so far.
    func sync(schedule: KitchenSchedule, finished: Set<String>, minute: Int, clockStart: Date, dishName: String) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for placement in schedule.placements where !finished.contains(placement.id) {
            let task = placement.task
            let component = task.component
            if task.handsMinutes > 0 && placement.start > minute {
                let body = component.isEmpty
                    ? String(localized: "Jetzt dran")
                    : String(localized: "\(component) · jetzt dran")
                add(id: Self.prefix + "start." + task.id, title: task.name, body: body, thread: dishName,
                    at: clockStart.addingTimeInterval(TimeInterval(placement.start * 60)), center: center)
            }
            if task.unattendedMinutes > 0 && placement.end > minute {
                let body = component.isEmpty
                    ? String(localized: "Die Zeit ist um")
                    : String(localized: "\(component) · die Zeit ist um")
                add(id: Self.prefix + "end." + task.id, title: task.name, body: body, thread: dishName,
                    at: clockStart.addingTimeInterval(TimeInterval(placement.end * 60)), center: center)
            }
        }
    }

    /// No more reminders: the clock is paused or cooking has ended.
    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private func add(id: String, title: String, body: String, thread: String, at date: Date,
                     center: UNUserNotificationCenter) {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = thread
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        center.add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Shown with sound even while the app is in front: the phone lies on
    /// the counter, the cook's eyes are on the pan.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
