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
}
