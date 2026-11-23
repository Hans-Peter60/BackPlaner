//
//  CookActivityWidget.swift
//  CookPlannerWidgets
//
//  The dish being cooked, on the lock screen and in the Dynamic Island:
//  the countdown to the plate, the step in the cook's hands, the next one
//  with its own countdown. The app sets the next step's start as the stale
//  date, so "Jetzt dran" appears on the device without an update.
//

import ActivityKit
import SwiftUI
import WidgetKit

enum CookWidgetTheme {
    static let accent = Color(red: 0.85, green: 0.45, blue: 0.18)
}

struct CookActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPaused ? "pause.circle.fill" : "frying.pan")
                        .font(.headline)
                        .foregroundStyle(CookWidgetTheme.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    remaining(context)
                        .font(.headline)
                        .foregroundStyle(CookWidgetTheme.accent)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.headline)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.dishName)
                            .font(.caption)
                            .lineLimit(1)
                        nextLine(context)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "frying.pan")
                    .foregroundStyle(CookWidgetTheme.accent)
            } compactTrailing: {
                remaining(context)
                    .font(.caption2)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "frying.pan")
                    .foregroundStyle(CookWidgetTheme.accent)
            }
            .keylineTint(CookWidgetTheme.accent)
        }
    }

    /// The countdown to the plate; while paused, the minutes left as a number.
    private func remaining(_ context: ActivityViewContext<CookActivityAttributes>) -> Text {
        if context.state.isPaused {
            return Text("\(context.state.pausedRemainingMinutes) Min.")
        }
        return Text(context.state.finishDate, style: .timer).monospacedDigit()
    }

    @ViewBuilder
    private func nextLine(_ context: ActivityViewContext<CookActivityAttributes>) -> some View {
        if let next = context.state.nextStep, let date = context.state.nextDate, !context.isNextDue, !context.state.isPaused {
            Text("Gleich \(Text(date, style: .timer)) · \(next)")
                .font(.caption2)
                .lineLimit(1)
        } else if context.state.runningCount > 0 {
            Text("\(context.state.runningCount) läuft von allein")
                .font(.caption2)
                .lineLimit(1)
        }
    }
}

private extension ActivityViewContext where Attributes == CookActivityAttributes {
    /// The next step's time has come on the device, without an update.
    var isNextDue: Bool { isStale && state.nextStep != nil }

    /// What the cook should be doing now.
    var headline: String {
        if state.isPaused { return String(localized: "Pause, die Uhr steht") }
        if isNextDue, let next = state.nextStep { return next }
        if let current = state.currentStep { return current }
        if state.doneCount >= state.totalCount { return String(localized: "Fertig, anrichten!") }
        return String(localized: "Hände frei")
    }

    var label: LocalizedStringKey {
        if state.isPaused { return "Pause" }
        if isNextDue { return "Jetzt dran" }
        if state.currentStep != nil { return "Jetzt" }
        return "Warten"
    }
}

private struct LockScreenView: View {

    let context: ActivityViewContext<CookActivityAttributes>

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.label)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(CookWidgetTheme.accent)
                Text(context.headline)
                    .font(.headline)
                    .lineLimit(2)
                if let component = context.state.currentComponent, !context.isNextDue, !context.state.isPaused {
                    Text(component)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // While paused the next step's countdown would run on; the line waits.
                if let next = context.state.nextStep, let date = context.state.nextDate, !context.isNextDue, !context.state.isPaused {
                    Text("Gleich \(Text(date, style: .timer)) · \(next)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "frying.pan")
                    .font(.title3)
                    .foregroundStyle(CookWidgetTheme.accent)
                if context.state.isPaused {
                    Text("\(context.state.pausedRemainingMinutes) Min.")
                        .font(.title3.weight(.bold))
                } else {
                    Text(context.state.finishDate, style: .timer)
                        .monospacedDigit()
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                }
                Text("\(context.state.doneCount) von \(context.state.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
