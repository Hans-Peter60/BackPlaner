//
//  EventKitExport.swift
//  BackPlaner
//
//  Two ways out of the app through EventKit: a plan's steps into the
//  calendar, so the household sees when the oven is taken, and a shopping
//  list into Apple Reminders, which can be shared with the family. Both ask
//  for access the first time — the calendar for writing only, reminders in
//  full, because a list has to be found or created there — and throw
//  `accessDenied` when the person refused, which the views turn into a
//  pointer to the iOS settings.
//
//  With write-only access the app cannot see the entries it made, so every
//  export adds new entries; the views say so before they run.
//

import BakePlannerCore
import EventKit
import Foundation

enum EventKitExportError: Error {
    /// The person refused, now or earlier.
    case accessDenied
    /// No calendar or reminder account to write into.
    case noTarget
}

enum CalendarExport {

    /// Writes `entries` into the default calendar and returns how many.
    static func add(_ entries: [PlanCalendarEntry]) async throws -> Int {
        let store = EKEventStore()
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestWriteOnlyAccessToEvents()
        }
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .writeOnly || status == .fullAccess else { throw EventKitExportError.accessDenied }
        guard let calendar = store.defaultCalendarForNewEvents else { throw EventKitExportError.noTarget }

        for entry in entries {
            let event = EKEvent(eventStore: store)
            event.title = entry.title
            event.startDate = entry.start
            event.endDate = entry.end
            event.notes = entry.notes
            event.calendar = calendar
            try store.save(event, span: .thisEvent, commit: false)
        }
        try store.commit()
        AppLog.notifications.info("Calendar: \(entries.count) entries added")
        return entries.count
    }
}

enum RemindersExport {

    /// The list in Reminders the shopping lists go into; created when missing.
    static let listName = "BakePlanner"

    /// Writes `items` as open reminders into the app's list and returns how many.
    static func send(_ items: [String]) async throws -> Int {
        let store = EKEventStore()
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { throw EventKitExportError.accessDenied }

        let list = try listCalendar(in: store)
        for title in items {
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.calendar = list
            try store.save(reminder, commit: false)
        }
        try store.commit()
        AppLog.notifications.info("Reminders: \(items.count) items sent to \(listName)")
        return items.count
    }

    /// The app's list, or a new one in the account new reminders go to.
    private static func listCalendar(in store: EKEventStore) throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == listName }) {
            return existing
        }
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .calDAV })
                ?? store.sources.first(where: { $0.sourceType == .local }) else {
            throw EventKitExportError.noTarget
        }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = listName
        list.source = source
        try store.saveCalendar(list, commit: true)
        return list
    }
}
