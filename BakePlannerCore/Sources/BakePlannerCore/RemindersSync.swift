//
//  RemindersSync.swift
//  BakePlannerCore
//
//  What sending a shopping list to Apple Reminders does with each line,
//  against what the chosen Reminders list already holds. Every reminder
//  the app makes carries a link to its line ("bakeplanner://shopping/<id>"),
//  so sending again finds it: an open one whose wording changed is
//  updated, one already ticked off in Reminders is left alone (it was
//  bought), and a line the list already has under the same words — typed
//  in by hand, say — is not added twice. Everything else is added.
//

import Foundation

public enum RemindersSync {

    public static let markerPrefix = "bakeplanner://shopping/"

    /// A line of the app's shopping list.
    public struct Line: Equatable, Sendable {
        public let id: String?
        public let title: String
        public init(id: String?, title: String) {
            self.id = id
            self.title = title
        }
    }

    /// A reminder already in the chosen list.
    public struct Existing: Equatable, Sendable {
        /// The reminder's own identifier in EventKit.
        public let identifier: String
        public let title: String
        public let url: URL?
        public let isCompleted: Bool
        public init(identifier: String, title: String, url: URL?, isCompleted: Bool) {
            self.identifier = identifier
            self.title = title
            self.url = url
            self.isCompleted = isCompleted
        }
    }

    public enum Action: Equatable, Sendable {
        case add(title: String, url: URL?)
        case update(identifier: String, title: String)
    }

    public struct Plan: Equatable, Sendable {
        public var actions: [Action] = []
        /// Lines already there as they are, or ticked off in Reminders.
        public var unchanged = 0

        public var added: Int { actions.filter { if case .add = $0 { true } else { false } }.count }
        public var updated: Int { actions.count - added }
    }

    public static func marker(for id: String) -> URL? {
        URL(string: markerPrefix + id)
    }

    public static func plan(_ lines: [Line], existing: [Existing]) -> Plan {
        var plan = Plan()
        let byMarker = Dictionary(existing.compactMap { item in item.url.map { ($0.absoluteString, item) } },
                                  uniquingKeysWith: { first, _ in first })
        let openTitles = Set(existing.filter { !$0.isCompleted }.map { comparable($0.title) })
        for line in lines {
            let url = line.id.flatMap(marker(for:))
            if let url, let known = byMarker[url.absoluteString] {
                if known.isCompleted || known.title == line.title {
                    plan.unchanged += 1
                } else {
                    plan.actions.append(.update(identifier: known.identifier, title: line.title))
                }
            } else if openTitles.contains(comparable(line.title)) {
                plan.unchanged += 1
            } else {
                plan.actions.append(.add(title: line.title, url: url))
            }
        }
        return plan
    }

    private static func comparable(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
