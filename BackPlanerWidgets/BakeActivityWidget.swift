//
//  BakeActivityWidget.swift
//  BackPlanerWidgets
//
//  The Live Activity of a running plan on the lock screen and in the Dynamic
//  Island: the step coming up with a running countdown, and "Jetzt fällig"
//  once its time has come. The app sets the step's time as the stale date,
//  so the switch happens on the device without an update.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct BakeActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BakeActivityAttributes.self) { context in
            LockScreenView(context: context)
                .widgetURL(PlanSnapshot.scheduledStepsURL)
                .activityBackgroundTint(WidgetTheme.backgroundTop)
                .activitySystemActionForegroundColor(WidgetTheme.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: context.isDue ? "bell.fill" : "timer")
                        Text(context.state.stepDate, format: .dateTime.hour().minute())
                    }
                    .font(.headline)
                    .foregroundStyle(WidgetTheme.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context)
                        .font(.headline)
                        .foregroundStyle(WidgetTheme.accent)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.instruction)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.recipeName)
                            .font(.caption)
                            .lineLimit(1)
                        followingLine(context)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The bottom row runs into the island's rounded corners,
                    // which shaved the first and last glyphs.
                    .padding(.horizontal, 10)
                }
            } compactLeading: {
                Image(systemName: context.isDue ? "bell.fill" : "timer")
                    .foregroundStyle(WidgetTheme.accent)
            } compactTrailing: {
                countdown(context)
                    .font(.caption2)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: context.isDue ? "bell.fill" : "timer")
                    .foregroundStyle(WidgetTheme.accent)
            }
            .widgetURL(PlanSnapshot.scheduledStepsURL)
            .keylineTint(WidgetTheme.accent)
        }
    }

    /// Counts down to the step and, once it has passed, up from it.
    private func countdown(_ context: ActivityViewContext<BakeActivityAttributes>) -> Text {
        Text(context.state.stepDate, style: .timer)
            .monospacedDigit()
    }

    @ViewBuilder
    private func followingLine(_ context: ActivityViewContext<BakeActivityAttributes>) -> some View {
        if let following = context.state.followingInstruction,
           let date = context.state.followingDate {
            Text("Danach \(Text(date, format: .dateTime.hour().minute())) · \(following)")
                .font(.caption2)
                .lineLimit(1)
        }
    }
}

private extension ActivityViewContext where Attributes == BakeActivityAttributes {
    /// Due either because the stale date (the step's time) has passed on the
    /// device, or because the step was already due when the app sent the
    /// content — in which case there is no stale date at all.
    var isDue: Bool { isStale || state.isDue }
}

private struct LockScreenView: View {

    let context: ActivityViewContext<BakeActivityAttributes>

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.isDue ? "Jetzt fällig" : "Als Nächstes")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(WidgetTheme.accent)
                Text(context.state.instruction)
                    .font(.headline)
                    .foregroundStyle(WidgetTheme.title)
                    .lineLimit(2)
                Text(context.attributes.recipeName)
                    .font(.caption)
                    .foregroundStyle(WidgetTheme.subtitle)
                    .lineLimit(1)
                if let following = context.state.followingInstruction,
                   let date = context.state.followingDate {
                    Text("Danach \(Text(date, format: .dateTime.hour().minute())) · \(following)")
                        .font(.caption2)
                        .foregroundStyle(WidgetTheme.subtitle)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: context.isDue ? "bell.fill" : "timer")
                    .font(.title3)
                    .foregroundStyle(WidgetTheme.accent)
                Text(context.state.stepDate, format: .dateTime.hour().minute())
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WidgetTheme.title)
                Text(context.state.stepDate, style: .timer)
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(WidgetTheme.subtitle)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
            }
        }
        .padding()
    }
}
