//
//  CookRunState.swift
//  CookPlanner
//
//  What the cook mode knows about the run under way, kept in UserDefaults
//  at every change: when the clock started, the pauses, every tick. If the
//  system ends the app while a roast is in the oven, the next launch opens
//  the cook mode again where it was, instead of losing the run and leaving
//  the alarms and the Live Activity of a run nobody can see.
//

import Foundation

struct CookRunState: Codable, Equatable {

    /// One tick of the cook, in order, for taking the last one back.
    struct Tick: Codable, Equatable, Hashable {
        enum Kind: String, Codable {
            /// The step is done.
            case done
            /// The hands-on part of a pot or oven step is done; it runs on its own now.
            case hands
        }
        var id: String
        var kind: Kind
    }

    var dishID: String
    var startedAt: Date
    var pausedAt: Date?
    var pausedSeconds: TimeInterval
    var finished: [String: Int]
    var handsDone: [String: Int]
    var ticks: [Tick]
    var doneSeconds: [String: Int]
    var handsDoneSeconds: [String: Int]
    var startSeconds: [String: Int]

    private static let key = "cook.runState"
    /// A run older than this is not taken up again: the meal is long over.
    static let resumeWithin: TimeInterval = 6 * 60 * 60

    static func load() -> CookRunState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CookRunState.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Whether the run is recent enough to be taken up again.
    var isResumable: Bool {
        Date().timeIntervalSince(startedAt) < Self.resumeWithin
    }

    /// Clears what a run that is not continued may have left behind:
    /// alarms, reminders and the Live Activity on the lock screen.
    @MainActor
    static func cleanUpLeftovers() {
        CookReminders.shared.cancelAll()
        CookAlarms.shared.cancelAll()
        CookActivityManager.shared.endAll()
    }
}
