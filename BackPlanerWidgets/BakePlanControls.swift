//
//  BakePlanControls.swift
//  BackPlanerWidgets
//
//  Controls for Control Center, the Lock Screen and the Action button:
//  "Schritt erledigt" ticks the step that is due right now off the plan,
//  "Geplante Schritte" opens the app at the plan. Both run in the widget
//  extension and work the way the widget's own button does: the step
//  leaves the plan snapshot at once and is noted for the app, which takes
//  it out of the plan with its reminder the next time it runs
//  (PendingWidgetActions).
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Schritt erledigt

struct MarkStepDoneControl: ControlWidget {

    static let kind = "de.hpm64625.BackPlaner.markStepDone"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: MarkCurrentStepDoneControlIntent()) {
                Label("Schritt erledigt", systemImage: "checkmark.circle")
            }
        }
        .displayName("Schritt erledigt")
        .description("Hakt den fälligen Schritt des Backplans ab.")
    }
}

/// Ticks off the step that is due right now — the one the widget shows.
/// With no step due or ahead, nothing happens.
struct MarkCurrentStepDoneControlIntent: AppIntent {

    static let title: LocalizedStringResource = "Fälligen Schritt erledigen"
    static let description = IntentDescription("Markiert den fälligen Schritt des Backplans als erledigt.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        guard let snapshot = PlanSnapshot.load(),
              let current = snapshot.currentStep(at: Date()) else { return .result() }
        try? snapshot.removingStep(id: current.step.id).save()
        try? PendingWidgetActions.appendDone(stepID: current.step.id)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Geplante Schritte

struct OpenPlanControl: ControlWidget {

    static let kind = "de.hpm64625.BackPlaner.openPlan"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenPlanControlIntent()) {
                Label("Geplante Schritte", systemImage: "list.bullet.clipboard")
            }
        }
        .displayName("Geplante Schritte")
        .description("Öffnet BakePlanner bei den geplanten Schritten.")
    }
}

/// Opens the app at "Geplante Schritte", through the same URL the Live
/// Activity and the widget use.
struct OpenPlanControlIntent: AppIntent {

    static let title: LocalizedStringResource = "Geplante Schritte öffnen"
    static let description = IntentDescription("Öffnet BakePlanner bei den geplanten Schritten.")
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(PlanSnapshot.scheduledStepsURL))
    }
}
