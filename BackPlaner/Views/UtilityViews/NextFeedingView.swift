//
//  NextFeedingView.swift
//  BackPlaner
//
//  "Nächste Fütterung: Morgen 18:00" for a recipe that refreshes on a
//  rhythm — a sourdough starter. Shown in the recipe's detail view beside
//  the dough yield and in the edit view under the rhythm, so the date the
//  automatic planning will pick is visible wherever the rhythm is.
//

import SwiftUI

struct NextFeedingView: View {

    /// From `RecurringBakePlanner.nextOccurrence`; `nil` while the recipe
    /// has no bake yet to measure the rhythm from.
    let date: Date?

    var body: some View {
        // Re-evaluated once a minute, so "Heute" turns into the date at
        // midnight without the view being rebuilt.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 4) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption)
                    .accessibilityHidden(true)
                if let date {
                    Text("Nächste Fütterung:")
                    + Text(verbatim: " ")
                    + StepTiming.dayLabel(for: date, now: context.date)
                    + Text(verbatim: " ")
                    + Text(date, format: .dateTime.hour().minute())
                } else {
                    Text("Nächste Fütterung: nach dem ersten Backen")
                }
            }
            .font(Theme.bodyFont(15))
            .foregroundColor(Theme.accentText)
            .accessibilityElement(children: .combine)
        }
    }
}
