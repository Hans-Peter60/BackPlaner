//
//  WidgetIntents.swift
//  BackPlanerWidgets
//
//  "Erledigt" on the home-screen widget. Runs in the widget extension: it
//  takes the step out of the plan snapshot, so the widget shows the next
//  one at once, and notes the step for the app, which removes it from the
//  plan and its reminder the next time it runs (PendingWidgetActions).
//

import AppIntents
import WidgetKit

struct MarkStepDoneWidgetIntent: AppIntent {

    static let title: LocalizedStringResource = "Schritt erledigt"
    static let description = IntentDescription("Markiert den Schritt im Widget als erledigt.")
    /// Not offered in Shortcuts or Spotlight: the app's own "Schritt
    /// erledigt" intent does the whole job there.
    static let isDiscoverable = false

    @Parameter(title: "Schritt")
    var stepID: String

    init() {}

    init(stepID: String) {
        self.stepID = stepID
    }

    func perform() async throws -> some IntentResult {
        if let snapshot = PlanSnapshot.load() {
            try? snapshot.removingStep(id: stepID).save()
        }
        try? PendingWidgetActions.appendDone(stepID: stepID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
