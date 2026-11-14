//
//  CalendarConflictCheck.swift
//  BackPlaner
//
//  Reads the baker's calendar for the span of a plan and asks the package
//  where the appointments fall into the moments the plan needs them. Only
//  with the setting "Kalender beim Planen prüfen" on (a Pro feature), and
//  with full calendar access, which iOS asks for the first time. Entries
//  the app wrote itself ("Rezept: Schritt") are no appointments.
//

import BakePlannerCore
import EventKit
import Foundation

enum CalendarConflictCheck {

    enum Outcome: Equatable {
        case off
        case denied
        case conflicts([CalendarConflict])
    }

    /// Whether the check runs at all: the setting is on and the feature unlocked.
    @MainActor
    static var isEnabled: Bool {
        AppSettings.storedCalendarCheck && Entitlements.shared.isUnlocked(.calendarCheck)
    }

    /// The plan's conflicts with the calendar, `.denied` when the person
    /// refused access, `.off` when the check is not switched on.
    @MainActor
    static func check(_ plan: BakePlan) async -> Outcome {
        guard isEnabled else { return .off }
        let store = EKEventStore()
        // Also asked when the calendar export was granted writing only:
        // reading needs the full access, which iOS offers to upgrade to.
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined || status == .writeOnly {
            _ = try? await store.requestFullAccessToEvents()
        }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return .denied }
        return .conflicts(CalendarConflicts.find(in: plan, events: events(for: plan, in: store)))
    }

    /// The timed appointments between the plan's first and last moment.
    private static func events(for plan: BakePlan, in store: EKEventStore) -> [CalendarEvent] {
        let dates = plan.plannedSteps.map(\.date) + [plan.baseDate, plan.date]
        guard let start = dates.min(), let end = dates.max() else { return [] }
        let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-3600),
                                                 end: end.addingTimeInterval(3600), calendars: nil)
        let ownPrefix = "\(plan.recipeName): "
        return store.events(matching: predicate).compactMap { event in
            guard let title = event.title, !title.hasPrefix(ownPrefix),
                  event.availability != .free else { return nil }
            return CalendarEvent(title: title, start: event.startDate, end: event.endDate, isAllDay: event.isAllDay)
        }
    }

    /// The outcome as plan hints: one line per conflict, or the pointer to
    /// the settings when access was refused.
    @MainActor
    static func issues(for outcome: Outcome) -> [BakePlanIssue] {
        let locale = AppSettings.locale
        switch outcome {
        case .off:
            return []
        case .denied:
            return [BakePlanIssue(severity: .hint,
                                  message: String(localized: "Kalender: Der Zugriff ist nicht erlaubt. Erlaube ihn in den iOS-Einstellungen unter BakePlanner, dann prüft die App Deine Termine.", locale: locale))]
        case .conflicts(let conflicts):
            let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
            return conflicts.map { conflict in
                let span = "\(conflict.event.start.formatted(time))–\(conflict.event.end.formatted(time))"
                return BakePlanIssue(severity: .hint,
                                     message: String(localized: "Kalender: „\(conflict.event.title)“ (\(span)) fällt in „\(conflict.step)“ um \(conflict.stepDate.formatted(time)).", locale: locale))
            }
        }
    }

    /// Short lines for the baking day's rows: "„Zahnarzt“ 10:30–11:10 · Teig formen".
    @MainActor
    static func notes(for outcome: Outcome) -> [String] {
        let locale = AppSettings.locale
        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
        switch outcome {
        case .off: return []
        case .denied: return [String(localized: "Kalenderzugriff nicht erlaubt", locale: locale)]
        case .conflicts(let conflicts):
            return conflicts.map { "„\($0.event.title)“ \($0.event.start.formatted(time))–\($0.event.end.formatted(time)) · \($0.step)" }
        }
    }
}
