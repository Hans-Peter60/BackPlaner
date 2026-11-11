//
//  PantryReminders.swift
//  BackPlaner
//
//  A notification two weeks before a pantry item's best-before date, when
//  the setting is on. The pending requests are brought in line with the
//  pantry after every change and whenever the app comes forward, so an
//  item eaten up, re-dated or synced from another device never rings.
//

import BakePlannerCore
import CoreData
import Foundation
@preconcurrency import UserNotifications

enum PantryReminders {

    static let identifierPrefix = "pantry-expiry-"

    /// Replaces every pantry reminder with one per item that still has a
    /// reminder date ahead; none while the setting is off or the feature
    /// locked. Asks for permission the first time.
    @MainActor
    static func reconcile(in context: NSManagedObjectContext) {
        let items = (try? CoreDataPantryStore(context: context).items()) ?? []
        reconcile(items: items)
    }

    @MainActor
    static func reconcile(items: [StoredPantryItem], now: Date = Date()) {
        // Read on the main actor; the notification centre answers elsewhere.
        let wanted = AppSettings.isPantryExpiryReminderEnabled && Entitlements.shared.isUnlocked(.pantry)
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            guard wanted else { return }
            let due = items.compactMap { item -> (StoredPantryItem, Date)? in
                Pantry.reminderDate(for: item, now: now).map { (item, $0) }
            }
            guard !due.isEmpty else { return }
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                switch settings.authorizationStatus {
                case .notDetermined:
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                        if granted { schedule(due) }
                    }
                case .authorized, .provisional:
                    schedule(due)
                default:
                    break
                }
            }
        }
    }

    private static func schedule(_ due: [(StoredPantryItem, Date)]) {
        let center = UNUserNotificationCenter.current()
        let locale = AppSettings.locale
        for (item, date) in due {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Vorrat: bald aufbrauchen", locale: locale)
            let day = (item.bestBefore ?? date).formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(locale))
            content.body = String(localized: "\(item.name) läuft am \(day) ab.", locale: locale)
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            // The key is stable per item, so a changed date replaces the request.
            let identifier = identifierPrefix + item.id.replacingOccurrences(of: "/", with: "_")
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }
}
