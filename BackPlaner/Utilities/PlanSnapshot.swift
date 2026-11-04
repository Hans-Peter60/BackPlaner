//
//  PlanSnapshot.swift
//  BackPlaner
//
//  The planned steps as a plain file in the App Group container, so the
//  widget, the Live Activity and the Watch app can show the plan without
//  the Core Data store. Compiled into the app, the widget extension and
//  the Watch app.
//
//  The app rewrites the file whenever planned steps change; the widget only
//  ever reads it.
//

import BakePlannerCore
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
        /// The component the step mixes and its ingredients, one line each
        /// ("• 800 g Weizenmehl 550") at the plan's amount — for the Watch,
        /// which has no recipe to look them up in. Nil when the step mixes
        /// nothing, or for a step of a public recipe.
        var componentName: String? = nil
        var ingredientLines: [String]? = nil
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
    static let dueGracePeriod: TimeInterval = CurrentStepRule.dueGracePeriod

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    static let empty = PlanSnapshot(steps: [], generatedAt: .distantPast)

    /// Where the app leaves its decision whether the widget may show the
    /// plan (see `Entitlements`): the extension cannot ask StoreKit or
    /// Firestore in time for a timeline. Absent means unlocked — the widget
    /// fails open like the app.
    static let widgetsUnlockedKey = "entitlements.widgetsUnlocked"

    static var widgetsUnlocked: Bool {
        UserDefaults(suiteName: appGroupIdentifier)?.object(forKey: widgetsUnlockedKey) as? Bool ?? true
    }

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
    /// the same rule (`CurrentStepRule`) to the live Core Data objects.
    func currentStep(at now: Date) -> (step: Step, isDue: Bool)? {
        CurrentStepRule.currentStep(in: steps, at: now, date: \.date)
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

    /// The snapshot without the step, for the widget and the Watch to show
    /// the next one the moment "Erledigt" is tapped.
    func removingStep(id: String) -> PlanSnapshot {
        PlanSnapshot(steps: steps.filter { $0.id != id }, generatedAt: Date())
    }
}
