//
//  WidgetActions.swift
//  BackPlaner
//
//  What the widget's buttons do, and how it reaches the app. Compiled into
//  both the app and the widget extension.
//
//  The widget extension cannot touch the Core Data store or the app's
//  reminders: the store lives in the app's own container, and local
//  notifications belong to the bundle that scheduled them. "Erledigt" on
//  the widget therefore takes the step out of the plan snapshot at once
//  (so the widget moves on) and leaves a note in the App Group; the app
//  carries it out in Core Data the next time it runs, before it rewrites
//  the snapshot. "Verschieben" needs the reminders moved, so it opens the
//  app on the step through a deep link.
//

import Foundation

/// Actions taken on the widget that the app still has to carry out.
struct PendingWidgetActions: Codable, Equatable {

    enum Kind: String, Codable {
        case done
    }

    struct Action: Codable, Equatable {
        /// `PlanSnapshot.Step.id`: the step's UUID, or its object URI for an
        /// old step without one.
        let stepID: String
        let kind: Kind
        let date: Date
    }

    var actions: [Action] = []

    private static let fileName = "widget-actions.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: PlanSnapshot.appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    static func load() -> PendingWidgetActions {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return PendingWidgetActions() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PendingWidgetActions.self, from: data)) ?? PendingWidgetActions()
    }

    func save() throws {
        guard let url = Self.fileURL else { throw CocoaError(.fileNoSuchFile) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Notes that the step was marked done on the widget.
    static func appendDone(stepID: String, at date: Date = Date()) throws {
        var pending = load()
        guard !pending.actions.contains(where: { $0.stepID == stepID && $0.kind == .done }) else { return }
        pending.actions.append(Action(stepID: stepID, kind: .done, date: date))
        try pending.save()
    }

    /// Hands the noted actions to the app and clears the note.
    static func take() -> [Action] {
        let pending = load()
        guard !pending.actions.isEmpty else { return [] }
        try? PendingWidgetActions().save()
        return pending.actions
    }
}

extension PlanSnapshot {
    /// Opens the app on the step, with the "Schritt verschieben" sheet up.
    static func shiftURL(for stepID: String) -> URL {
        var components = URLComponents()
        components.scheme = "bakeplanner"
        components.host = "scheduled-steps"
        components.queryItems = [URLQueryItem(name: "shift", value: stepID)]
        return components.url ?? scheduledStepsURL
    }

    /// The step a `shiftURL(for:)` names, nil for any other link.
    static func shiftStepID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "bakeplanner",
              url.host()?.lowercased() == "scheduled-steps",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "shift" })?.value,
              !id.isEmpty else { return nil }
        return id
    }

    /// The snapshot without the step, for the widget to show the next one
    /// the moment "Erledigt" is tapped.
    func removingStep(id: String) -> PlanSnapshot {
        PlanSnapshot(steps: steps.filter { $0.id != id }, generatedAt: Date())
    }
}
