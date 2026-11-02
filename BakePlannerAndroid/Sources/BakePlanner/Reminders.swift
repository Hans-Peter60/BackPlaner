import BakePlannerCore
import Foundation
#if os(Android)
// SkipFuseUI brings the UserNotifications types along on Android.
import SwiftUI
#else
import UserNotifications
#endif

/// The reminders of planned steps, one notification per step still ahead,
/// worded as on the iPhone (PlanReminder). On Android they are delivered
/// through WorkManager: punctual as a rule, but a phone left idle for long
/// may show one late. Taps open the app; actions like the iPhone's
/// "Erledigt" do not exist there. On the main actor, like the model that
/// calls it, so no step crosses an isolation boundary.
@MainActor
enum Reminders {

    /// Asks for permission — Android 13 and later show the question once —
    /// and sets a reminder for every step of `steps` that lies ahead.
    /// Whether reminders may be shown at all.
    static func schedule(_ steps: [ScheduledStepData], recipe: RecipeExportData, now: Date = Date()) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        await add(steps, recipe: recipe, now: now)
        return true
    }

    /// Sets the reminders of steps that moved, at their new dates, without
    /// asking for permission again: the same identifiers replace the old
    /// requests. Steps now in the past get none.
    static func reschedule(_ steps: [ScheduledStepData], recipe: RecipeExportData?, now: Date = Date()) async {
        cancel(steps)
        await add(steps, recipe: recipe, now: now)
    }

    private static func add(_ steps: [ScheduledStepData], recipe: RecipeExportData?, now: Date) async {
        let center = UNUserNotificationCenter.current()
        for step in steps where step.date > now {
            guard let identifier = PlanReminder.identifier(of: step) else { continue }
            let content = UNMutableNotificationContent()
            content.title = PlanReminder.title
            content.body = PlanReminder.body(instruction: step.instruction,
                                             details: recipe.flatMap { PlanReminder.details(of: step, in: $0) })
            // The buttons on the notification and the question that follows
            // a postponement, in the app's language: Kotlin posts the
            // notification (ReminderWorker in Reminders.kt) and has no
            // catalog of its own.
            content.userInfo = [
                "action.done": String(localized: "Erledigt", bundle: .module),
                "action.postpone": String(localized: "Verschieben um …", bundle: .module),
                "action.minutes": String(localized: "Minuten", bundle: .module),
                "action.confirmTitle": String(localized: "Erinnerung verschieben", bundle: .module),
                "action.confirmBody": String(localized: "Sollen alle nachfolgenden Schritte dieses Rezepts ebenfalls verschoben werden?", bundle: .module),
                "action.only": String(localized: "Nur diesen Schritt", bundle: .module),
                "action.following": String(localized: "Alle nachfolgenden", bundle: .module),
            ]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: step.date.timeIntervalSince(now),
                                                            repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            } catch {
                logger.error("could not set the reminder of \(step.instruction): \(error)")
            }
        }
    }

    /// Takes back the reminders of these steps — done, or their plan
    /// deleted or replaced.
    static func cancel(_ steps: [ScheduledStepData]) {
        let identifiers = steps.compactMap(PlanReminder.identifier(of:))
        guard !identifiers.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
