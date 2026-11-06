//
//  BakeAlarmManager.swift
//  BackPlaner
//
//  Real alarms for the steps of a plan, beside the reminders. A reminder
//  is a notification: it goes under when the iPhone is on silent or in a
//  Focus, which at three in the morning means the bread stays in the
//  oven. An AlarmKit alarm rings through both. The setting "Wecker" says
//  which steps get one — none, the oven steps, or every step
//  (AlarmStepSelection in the package).
//
//  The alarms are kept in step with the plan by reconciliation rather than
//  by hooking every place a step is done, moved or deleted: whenever the
//  plan changes, PlanSnapshotPublisher.refresh runs and calls `sync` with
//  every scheduled step. The alarm's id is the step's id, so an alarm whose
//  step is gone is cancelled, a step whose alarm is missing or at the wrong
//  time gets one, and the rest stay as they are. An alarm whose time has
//  passed is never set again.
//
//  The alert shows the step, a system "Stopp" button and "Erledigt", which
//  stops the alarm and takes the step off the plan the way the widget and
//  the Watch do: through PendingWidgetActions, applied on the next refresh.
//

import AlarmKit
import AppIntents
import BakePlannerCore
import SwiftUI

/// What travels with an alarm; the alert itself is system UI.
struct BakeAlarmMetadata: AlarmMetadata {
    let stepID: UUID
    let recipeName: String
}

@MainActor
final class BakeAlarmManager {

    static let shared = BakeAlarmManager()

    private let manager = AlarmManager.shared

    private init() {}

    /// Whether alarms may be scheduled at all.
    var isAuthorized: Bool {
        manager.authorizationState == .authorized
    }

    var isDenied: Bool {
        manager.authorizationState == .denied
    }

    /// Asks once; afterwards the state is what the person decided.
    func requestAuthorization() async -> Bool {
        do {
            return try await manager.requestAuthorization() == .authorized
        } catch {
            AppLog.notifications.error("Alarm authorization failed: \(error)")
            return false
        }
    }

    /// Brings the alarms in line with `steps`, the plan as scheduled right
    /// now: under the setting `scope`, the steps that should ring get an
    /// alarm at their date, every other alarm goes. Without authorization
    /// nothing is scheduled — the settings ask for it; a scope of `.off`
    /// cancels what is left.
    func sync(steps: [ScheduledStepData], scope: AlarmStepScope = AppSettings.storedAlarmScope, now: Date = Date()) {
        let existing: [Alarm]
        do {
            existing = try manager.alarms
        } catch {
            AppLog.notifications.error("Alarms could not be read: \(error)")
            return
        }

        let wanted: [UUID: ScheduledStepData]
        if scope == .off || !isAuthorized {
            wanted = [:]
        } else {
            wanted = Dictionary(AlarmStepSelection.steps(for: scope, in: steps, now: now)
                                    .compactMap { step in step.id.map { ($0, step) } },
                                uniquingKeysWith: { first, _ in first })
        }

        var cancelled = 0
        var scheduled = 0
        for alarm in existing where wanted[alarm.id] == nil {
            try? manager.cancel(id: alarm.id)
            cancelled += 1
        }
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, step) in wanted {
            if let alarm = existingByID[id], case .fixed(let date)? = alarm.schedule,
               abs(date.timeIntervalSince(step.date)) < 30 {
                continue
            }
            if existingByID[id] != nil {
                try? manager.cancel(id: id)
            }
            Task { [manager] in
                do {
                    _ = try await manager.schedule(id: id, configuration: Self.configuration(for: step, id: id))
                } catch {
                    AppLog.notifications.error("Alarm for \(step.instruction, privacy: .public) could not be set: \(error)")
                }
            }
            scheduled += 1
        }
        if cancelled > 0 || scheduled > 0 {
            AppLog.notifications.info("Alarms: \(scheduled) set, \(cancelled) cancelled, scope \(scope.rawValue, privacy: .public)")
        }
    }

    /// Cancels every alarm — the setting turned off.
    func cancelAll() {
        guard let existing = try? manager.alarms else { return }
        for alarm in existing {
            try? manager.cancel(id: alarm.id)
        }
        AppLog.notifications.info("Alarms: all \(existing.count) cancelled, scope off")
    }

    /// A one-shot alarm at the step's date: the step as title, the system
    /// stop button, and "Erledigt".
    private static func configuration(for step: ScheduledStepData, id: UUID) -> AlarmManager.AlarmConfiguration<BakeAlarmMetadata> {
        let title = LocalizedStringResource(String.LocalizationValue("\(step.recipeName) · \(step.instruction)"))
        let done = AlarmButton(text: LocalizedStringResource("Erledigt", bundle: .main),
                               textColor: .white,
                               systemImageName: "checkmark.circle")
        let stop = AlarmButton(text: LocalizedStringResource("Stopp", bundle: .main),
                               textColor: .white,
                               systemImageName: "stop.fill")
        let alert = AlarmPresentation.Alert(title: title, stopButton: stop,
                                            secondaryButton: done, secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                         metadata: BakeAlarmMetadata(stepID: id, recipeName: step.recipeName),
                                         tintColor: Theme.accentText)
        return .alarm(schedule: .fixed(step.date),
                      attributes: attributes,
                      secondaryIntent: MarkAlarmStepDoneIntent(stepID: id.uuidString),
                      sound: .default)
    }
}

/// "Erledigt" on the alarm: stops the alarm and notes the step as done,
/// the way the widget does; the app takes the step off the plan, reminder
/// included, on its next refresh.
struct MarkAlarmStepDoneIntent: LiveActivityIntent {

    static let title: LocalizedStringResource = "Schritt erledigt"
    static let isDiscoverable = false

    @Parameter(title: "Schritt")
    var stepID: String

    init() {}

    init(stepID: String) {
        self.stepID = stepID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: stepID) {
            try? AlarmManager.shared.stop(id: id)
        }
        try? PendingWidgetActions.appendDone(stepID: stepID)
        await MainActor.run {
            PlanSnapshotPublisher.shared.refresh()
        }
        return .result()
    }
}
