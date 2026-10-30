//
//  NotificationProbeView.swift
//  BakePlannerProbe
//
//  The reminders the way BakePlanner uses them (NotificationManager.swift):
//  permission, a reminder at a fixed time with extra data, a category with
//  "Erledigt" and a "Verschieben um …" action that takes text, the list of
//  pending reminders, removing one by its identifier, and hearing back when
//  an action is tapped. What of this Skip carries over to Android is what
//  the probe is for.
//

import Foundation
import Observation
import SkipFuse
import SkipFuseUI
#if canImport(UserNotifications)
import UserNotifications
#endif

/// What happened, newest first, for the screen to show.
@MainActor
@Observable
final class NotificationProbeLog {
    var entries: [String] = []

    func add(_ text: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        entries.insert("\(time)  \(text)", at: 0)
    }
}

/// Receives the reminders while the app runs and the actions tapped on them.
final class NotificationProbeDelegate: NSObject, UNUserNotificationCenterDelegate {
    let log: NotificationProbeLog

    init(log: NotificationProbeLog) {
        self.log = log
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let title = notification.request.content.body
        await log.add("Im Vordergrund angekommen: \(title)")
        return [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let body = response.notification.request.content.body
        let step = response.notification.request.content.userInfo["step"] as? String ?? "?"
        var text = "Aktion „\(action)“ bei „\(body)“ (Schritt \(step))"
        #if !os(Android)
        // Skip has no text-input actions on Android (first run, 30.10.2026).
        if let input = response as? UNTextInputNotificationResponse {
            text += ", eingegeben: „\(input.userText)“"
        }
        #endif
        await log.add(text)
    }
}

enum NotificationProbe {
    static let category = "probe.reminder"
    static let doneAction = "probe.done"
    static let postponeAction = "probe.postpone"

    /// Skip has no notification actions or categories on Android (first
    /// run, 30.10.2026): the reminders arrive there without buttons.
    static func registerCategory() {
        #if !os(Android)
        let done = UNNotificationAction(identifier: doneAction, title: "Erledigt", options: [])
        let postpone = UNTextInputNotificationAction(identifier: postponeAction,
                                                     title: "Verschieben um …",
                                                     options: [],
                                                     textInputButtonTitle: "Verschieben",
                                                     textInputPlaceholder: "Minuten")
        let category = UNNotificationCategory(identifier: NotificationProbe.category,
                                              actions: [done, postpone],
                                              intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        #endif
    }

    /// A reminder at a fixed minute, built like the app builds its own.
    static func schedule(id: String, step: String, text: String, at date: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Backhinweis"
        content.subtitle = "Gedrückt halten für Erledigt oder Verschieben"
        content.body = text
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = "probe"
        content.userInfo = ["step": step, "scheduledDate": date.timeIntervalSince1970]

        #if os(Android)
        // Skip cannot hand DateComponents to Android, so a calendar trigger
        // crashes there (second run, 30.10.2026); the time until the date
        // does the same for a one-off reminder.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        #else
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        #endif
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

struct NotificationProbeView: View {
    // Not private: Skip Fuse cannot bridge private state to Android.
    @State var log = NotificationProbeLog()
    @State var delegate: NotificationProbeDelegate?
    @State var pending: [String] = []

    var body: some View {
        Form {
            Section("1. Erlaubnis") {
                Button("Erlaubnis anfragen") {
                    Task {
                        do {
                            let granted = try await UNUserNotificationCenter.current()
                                .requestAuthorization(options: [.alert, .badge, .sound])
                            log.add(granted ? "Erlaubnis erteilt" : "Erlaubnis verweigert")
                        } catch {
                            log.add("Fehler bei der Erlaubnis: \(error.localizedDescription)")
                        }
                    }
                }
            }

            Section("2. Planen") {
                Button("Drei Erinnerungen: in 1, 2 und 3 Minuten") {
                    Task { await scheduleThree() }
                }
                Button("Erinnerung in 1 Minute, dann App schließen") {
                    Task { await scheduleOne(minutes: 1, id: "probe-closed", step: "9") }
                }
            }

            Section("3. Ausstehende") {
                Button("Ausstehende anzeigen") {
                    Task { await refreshPending() }
                }
                Button("Die 2-Minuten-Erinnerung löschen") {
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["probe-2"])
                    log.add("probe-2 gelöscht")
                    Task { await refreshPending() }
                }
                ForEach(pending, id: \.self) { id in
                    Text(id)
                }
            }

            Section("Protokoll") {
                if log.entries.isEmpty {
                    Text("Noch nichts passiert")
                        .foregroundStyle(.secondary)
                }
                ForEach(log.entries, id: \.self) { entry in
                    Text(entry)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Erinnerungen")
        .onAppear {
            if delegate == nil {
                let receiver = NotificationProbeDelegate(log: log)
                delegate = receiver
                UNUserNotificationCenter.current().delegate = receiver
                NotificationProbe.registerCategory()
                log.add("Bereit: Empfänger und Aktionen eingerichtet")
            }
        }
    }

    func scheduleThree() async {
        for minute in 1...3 {
            await scheduleOne(minutes: minute, id: "probe-\(minute)", step: "\(minute)")
        }
        await refreshPending()
    }

    func scheduleOne(minutes: Int, id: String, step: String) async {
        // On the next full minute and then `minutes` on, so the arrival is
        // easy to check against the clock.
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        let thisMinute = calendar.date(from: parts) ?? Date()
        let date = thisMinute.addingTimeInterval(TimeInterval(minutes * 60))
        let time = date.formatted(date: .omitted, time: .shortened)
        do {
            try await NotificationProbe.schedule(id: id, step: step, text: "Schritt \(step): Teig falten (geplant \(time))", at: date)
            log.add("\(id) geplant für \(time)")
        } catch {
            log.add("Fehler beim Planen von \(id): \(error.localizedDescription)")
        }
    }

    func refreshPending() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        // Untyped on Android, so cast each one.
        pending = requests.compactMap { ($0 as? UNNotificationRequest)?.identifier }.sorted()
        log.add("Ausstehend: \(pending.count)")
    }
}
