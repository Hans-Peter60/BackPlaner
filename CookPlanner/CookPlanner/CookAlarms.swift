//
//  CookAlarms.swift
//  CookPlanner
//
//  Real alarms for the moments that must not be missed: when a pot or the
//  oven has run its time. A reminder is a notification and stays silent
//  when the iPhone is on silent or in a Focus; an AlarmKit alarm rings
//  through both. The setting "Wecker für Topf und Ofen" turns them on;
//  such a step then gets no "die Zeit ist um" reminder beside its alarm.
//
//  Like the reminders, the alarms follow the live plan: `sync` runs with
//  every change and reconciles — an alarm whose step is done or gone is
//  cancelled, one at a moved time is set again, the rest stay.
//

import ActivityKit
import AlarmKit
import BakePlannerCore
import SwiftUI

/// What travels with an alarm; the alert itself is system UI.
struct CookAlarmMetadata: AlarmMetadata {
    let taskID: String
    let dishName: String
}

@MainActor
final class CookAlarms {

    static let shared = CookAlarms()

    private let manager = AlarmManager.shared
    /// The alarms set in this run: step id → alarm id and time. Only what
    /// AlarmKit has accepted is in here.
    private var scheduled: [String: (id: UUID, date: Date)] = [:]
    /// Scheduling and cancelling run one after the other, in the order
    /// they were asked for: a pause right after a tick must not find the
    /// tick's alarm still being created, to ring after the pause.
    private var queue: Task<Void, Never>?

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: CookSettings.alarmsKey) as? Bool ?? CookSettings.defaultAlarms
    }

    var isAuthorized: Bool { manager.authorizationState == .authorized }

    /// Asks once when the setting is on; answers whether alarms may ring.
    func requestAuthorization() async -> Bool {
        guard isEnabled else { return false }
        switch manager.authorizationState {
        case .authorized: return true
        case .denied: return false
        default: return (try? await manager.requestAuthorization()) == .authorized
        }
    }

    /// The steps that get an alarm at the end of their time on their own:
    /// not done, and ending after `minute`.
    func alarmTasks(in schedule: KitchenSchedule, finished: Set<String>, minute: Int) -> Set<String> {
        guard isEnabled, isAuthorized else { return [] }
        return Set(schedule.placements
            .filter { !finished.contains($0.id) && $0.task.unattendedMinutes > 0 && $0.end > minute }
            .map(\.id))
    }

    /// Brings the alarms in line with the live plan. `clockStart` is the
    /// wall-clock date of the plan's minute 0, the start plus the pauses.
    func sync(schedule: KitchenSchedule, finished: Set<String>, minute: Int, clockStart: Date, dishName: String) {
        let wanted = alarmTasks(in: schedule, finished: finished, minute: minute)
        enqueue { [self] in
            for (taskID, alarm) in scheduled where !wanted.contains(taskID) {
                try? manager.cancel(id: alarm.id)
                scheduled[taskID] = nil
            }
            for placement in schedule.placements where wanted.contains(placement.id) {
                let date = clockStart.addingTimeInterval(TimeInterval(placement.end * 60))
                if let alarm = scheduled[placement.id] {
                    if abs(alarm.date.timeIntervalSince(date)) < 30 { continue }
                    try? manager.cancel(id: alarm.id)
                    scheduled[placement.id] = nil
                }
                guard date.timeIntervalSinceNow > 1 else { continue }
                let id = UUID()
                let configuration = Self.configuration(for: placement.task, dishName: dishName, at: date)
                if (try? await manager.schedule(id: id, configuration: configuration)) != nil {
                    scheduled[placement.id] = (id, date)
                }
            }
        }
    }

    /// No more alarms: the clock is paused or cooking has ended. Also
    /// clears those an earlier run left, should the app have been closed.
    func cancelAll() {
        enqueue { [self] in
            for alarm in (try? manager.alarms) ?? [] {
                try? manager.cancel(id: alarm.id)
            }
            scheduled = [:]
        }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// A one-shot alarm: the step as title and the system stop button.
    private static func configuration(for task: KitchenTask, dishName: String,
                                      at date: Date) -> AlarmManager.AlarmConfiguration<CookAlarmMetadata> {
        let title = LocalizedStringResource(String.LocalizationValue(
            task.component.isEmpty ? "\(task.name) · die Zeit ist um" : "\(task.component): \(task.name) · die Zeit ist um"))
        let stop = AlarmButton(text: LocalizedStringResource("Stopp", bundle: .main),
                               textColor: .white,
                               systemImageName: "stop.fill")
        let alert = AlarmPresentation.Alert(title: title, stopButton: stop)
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                         metadata: CookAlarmMetadata(taskID: task.id, dishName: dishName),
                                         tintColor: Theme.accentText)
        return .alarm(schedule: .fixed(date), attributes: attributes, sound: .default)
    }
}
