//
//  NextFeedingView.swift
//  BackPlaner
//
//  "Nächste Fütterung: Morgen 18:00" for a recipe that refreshes on a
//  rhythm — a sourdough starter — or "Nächster Backtermin: …" for a bread
//  planned on one. The time is that of the first step, which the rhythm
//  keeps at the same time of day. Shown in the recipe's detail view beside
//  the dough yield and in the edit view under the rhythm, so the date the
//  automatic planning will pick is visible wherever the rhythm is.
//

import BakePlannerCore
import SwiftUI

struct NextFeedingView: View {

    /// From `RecurringBakePlanner.nextStart`; `nil` while the recipe has
    /// nothing yet to measure the rhythm from — no bake, or for a starter
    /// no feeding.
    let date: Date?
    /// Whether the recipe feeds a starter (`StarterRecipe.isStarterFeeding`)
    /// or bakes something; only the wording differs.
    var isStarter = true

    var body: some View {
        // Re-evaluated once a minute, so "Heute" turns into the date at
        // midnight without the view being rebuilt.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 4) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption)
                    .accessibilityHidden(true)
                switch (isStarter, date) {
                case (true, let date?):
                    Text("Nächste Fütterung: \(StepTiming.dayLabel(for: date, now: context.date)) \(date, format: .dateTime.hour().minute())")
                case (true, nil):
                    Text("Nächste Fütterung: nach der ersten Fütterung")
                case (false, let date?):
                    Text("Nächster Backtermin: \(StepTiming.dayLabel(for: date, now: context.date)) \(date, format: .dateTime.hour().minute())")
                case (false, nil):
                    Text("Nächster Backtermin: nach dem ersten Backen")
                }
            }
            .font(Theme.bodyFont(15))
            .foregroundColor(Theme.accentText)
            .accessibilityElement(children: .combine)
        }
    }
}
