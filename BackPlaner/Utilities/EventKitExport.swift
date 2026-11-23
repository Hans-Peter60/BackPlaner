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
//  With write-only access the calendar export cannot see the entries it
//  made, so every export adds new ones; the views say so before they run.
//  The shopping list has full access and finds its earlier reminders by
//  their link (RemindersSync), so sending again does not double them.
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

    /// The list the app makes when none is chosen; created when missing.
    static let listName = "BakePlanner"
    /// The chosen Reminders list, by its EventKit identifier.
    static let chosenListKey = "reminders.shoppingListID"

    /// A Reminders list to choose from.
    struct ListChoice: Identifiable, Hashable {
        let id: String
        let title: String
        let account: String
    }

    /// What one send did.
    struct Result: Equatable {
        let listTitle: String
        let added: Int
        let updated: Int
        let unchanged: Int
    }

    static var chosenListID: String? {
        get { UserDefaults.standard.string(forKey: chosenListKey) }
        set { UserDefaults.standard.set(newValue, forKey: chosenListKey) }
    }

    /// Asks for access once; throws when it was refused.
    private static func authorizedStore() async throws -> EKEventStore {
        let store = EKEventStore()
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { throw EventKitExportError.accessDenied }
        return store
    }

    /// The lists one can write into, the person's default list first.
    static func lists() async throws -> [ListChoice] {
        let store = try await authorizedStore()
        let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
        return store.calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .sorted { ($0.calendarIdentifier == defaultID ? 0 : 1, $0.title) < ($1.calendarIdentifier == defaultID ? 0 : 1, $1.title) }
            .map { ListChoice(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "") }
    }

    /// Brings `lines` into the chosen list (RemindersSync): new lines are
    /// added with a link back to them, changed ones updated, lines already
    /// there or ticked off in Reminders left alone.
    static func send(_ lines: [RemindersSync.Line]) async throws -> Result {
        let store = try await authorizedStore()
        let list = try listCalendar(in: store)
        let existing = await reminders(in: list, store: store).map { reminder in
            RemindersSync.Existing(identifier: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                                   url: reminder.url, isCompleted: reminder.isCompleted)
        }
        let plan = RemindersSync.plan(lines, existing: existing)
        for action in plan.actions {
            switch action {
            case .add(let title, let url):
                let reminder = EKReminder(eventStore: store)
                reminder.title = title
                reminder.url = url
                reminder.calendar = list
                try store.save(reminder, commit: false)
            case .update(let identifier, let title):
                guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { continue }
                reminder.title = title
                try store.save(reminder, commit: false)
            }
        }
        try store.commit()
        AppLog.notifications.info("Reminders: \(plan.added) added, \(plan.updated) updated, \(plan.unchanged) unchanged")
        return Result(listTitle: list.title, added: plan.added, updated: plan.updated, unchanged: plan.unchanged)
    }

    private static func reminders(in list: EKCalendar, store: EKEventStore) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: store.predicateForReminders(in: [list])) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    /// The chosen list; without one (or when it is gone) the app's own
    /// list, made in the account new reminders go to.
    private static func listCalendar(in store: EKEventStore) throws -> EKCalendar {
        if let id = chosenListID, let chosen = store.calendar(withIdentifier: id), chosen.allowsContentModifications {
            return chosen
        }
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
