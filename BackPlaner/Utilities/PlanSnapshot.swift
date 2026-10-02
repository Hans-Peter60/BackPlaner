//
//  PlanSnapshot.swift
//  BackPlaner
//
//  The planned steps as a plain file in the App Group container, so the
//  widget (and later the Live Activity) can read the plan without the Core
//  Data store. Compiled into both the app and the widget extension.
//
//  The app rewrites the file whenever planned steps change; the widget only
//  ever reads it.
//

import Foundation
import ActivityKit

struct PlanSnapshot: Codable, Equatable {

    /// One planned step, flattened from `NextStep`.
    struct Step: Codable, Equatable, Identifiable, Hashable {
        let id: String
        let recipeName: String
        let instruction: String
        let date: Date
        /// Minutes.
        let duration: Int
    }

    /// Sorted by date, earliest first.
    var steps: [Step]
    var generatedAt: Date

    static let appGroupIdentifier = "group.de.hpm64625.BackPlaner"
    private static let fileName = "plan-snapshot.json"

    /// Opens the planned steps in the app when the widget is tapped.
    static let scheduledStepsURL = URL(string: "bakeplanner://scheduled-steps")!

    /// How long a step counts as "due now" after its time has come. A step
    /// that is not marked done stays in the plan, so without this an old,
    /// finished plan would keep its last step on display forever.
    static let dueGracePeriod: TimeInterval = 60 * 60

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    static let empty = PlanSnapshot(steps: [], generatedAt: .distantPast)

    // MARK: Reading and writing

    static func load() -> PlanSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PlanSnapshot.self, from: data)
    }

    func save() throws {
        guard let url = Self.fileURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    // MARK: Which step to show

    /// The step that matters at `now`, and whether its time has already come.
    ///
    /// A step that became due within the grace period and is not marked done
    /// yet comes first — when the reminder fires, that is the thing to do,
    /// not the one after it. Otherwise the earliest step still ahead. A newer
    /// due step always supersedes an older one. The main menu card applies
    /// the same rule to the live Core Data objects.
    func currentStep(at now: Date) -> (step: Step, isDue: Bool)? {
        if let due = steps.last(where: { $0.date <= now }),
           now.timeIntervalSince(due.date) < Self.dueGracePeriod {
            return (due, true)
        }
        if let upcoming = steps.first(where: { $0.date > now }) {
            return (upcoming, false)
        }
        return nil
    }

    /// The moments after `now` at which `currentStep(at:)` can change: every
    /// step's start, and the end of every step's grace period. A widget
    /// timeline needs an entry at each of them.
    func changeDates(after now: Date) -> [Date] {
        var dates = Set<Date>()
        for step in steps {
            if step.date > now { dates.insert(step.date) }
            let graceEnd = step.date.addingTimeInterval(Self.dueGracePeriod)
            if graceEnd > now { dates.insert(graceEnd) }
        }
        return dates.sorted()
    }

    // MARK: Live Activity

    /// How far ahead a step may be for a Live Activity to show it. The system
    /// ends a Live Activity after eight hours anyway, so one for a step
    /// further away would only ever show a countdown that never arrives.
    static let liveActivityHorizon: TimeInterval = 8 * 60 * 60

    /// What the Live Activity should show at `now`, or `nil` when there is
    /// nothing within reach and any running activity should end.
    func liveActivityContent(at now: Date) -> (recipeName: String, state: BakeActivityAttributes.ContentState)? {
        guard let current = currentStep(at: now),
              current.step.date.timeIntervalSince(now) < Self.liveActivityHorizon
        else { return nil }

        let following = steps.first { $0.date > current.step.date }
        let state = BakeActivityAttributes.ContentState(
            instruction: current.step.instruction,
            stepDate: current.step.date,
            isDue: current.isDue,
            // One line in the activity, so a step like "Weizensauerteig\n
            // Zutaten mischen …" must not break after its first word.
            followingInstruction: following?.instruction.replacingOccurrences(of: "\n", with: " "),
            followingDate: following?.date
        )
        return (current.step.recipeName, state)
    }
}

/// The Live Activity of a running plan. The attributes name the recipe; the
/// state is the step on display and the one after it. Shared by the app,
/// which starts and updates the activity, and the widget extension, which
/// draws it.
struct BakeActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        var instruction: String
        /// When the step is due. Also the activity's stale date while it lies
        /// ahead, so the view can switch from the countdown to "Jetzt fällig"
        /// without an update.
        var stepDate: Date
        /// Already due when the content was made. An activity whose stale
        /// date is in the past is born stale and never shown at all, so the
        /// due state has to travel as a flag instead.
        var isDue: Bool
        var followingInstruction: String?
        var followingDate: Date?
    }

    var recipeName: String
}
