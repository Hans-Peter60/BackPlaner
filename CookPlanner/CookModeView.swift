//
//  CookModeView.swift
//  CookPlanner
//
//  The plan run against the clock: a countdown, what the hands do now,
//  what comes next, what runs on its own. The clock is the plan's; a step
//  finished early or late does not yet move the rest (replanning is on the
//  list in docs/Idee-Gegen-die-Uhr.md).
//

import BakePlannerCore
import SwiftUI

struct CookModeView: View {

    let plan: DishPlan

    @Environment(\.dismiss) private var dismiss
    @State private var startedAt: Date?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = startedAt.map { context.date.timeIntervalSince($0) } ?? 0
                content(elapsedSeconds: max(0, Int(elapsed)))
            }
            .warmBackground()
            .navigationTitle(Text(verbatim: plan.dish.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Beenden") { dismiss() }
                }
            }
        }
    }

    private func content(elapsedSeconds: Int) -> some View {
        let minute = elapsedSeconds / 60
        let placements = plan.schedule.placements
        let handsNow = placements.filter { $0.task.handsMinutes > 0 && $0.start <= minute && minute < $0.handsEnd }
        let unattended = placements.filter { $0.handsEnd <= minute && minute < $0.end }
        let upcoming = placements.filter { $0.start > minute }.sorted { ($0.start, $0.task.id) < ($1.start, $1.task.id) }
        let done = placements.filter { $0.end <= minute }
        let remaining = max(0, plan.schedule.makespan * 60 - elapsedSeconds)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                clock(remaining: remaining, minute: minute)

                if startedAt == nil {
                    Button {
                        startedAt = .now
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .font(Theme.bodyFont(17).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentBottom)
                } else {
                    section("Jetzt", systemImage: "hand.raised.fill") {
                        if handsNow.isEmpty {
                            if let next = upcoming.first {
                                Text("Hände frei, in \(next.start - minute) Min. weiter")
                                    .font(Theme.bodyFont(15))
                                    .foregroundColor(Theme.subtitle)
                            } else if done.count == placements.count {
                                Text("Fertig, anrichten!")
                                    .font(Theme.bodyFont(15))
                                    .foregroundColor(Theme.good)
                            }
                        }
                        ForEach(handsNow) { placement in
                            stepLine(placement, detail: "noch \(placement.handsEnd - minute) Min.")
                        }
                    }
                    if !upcoming.isEmpty {
                        section("Gleich", systemImage: "arrow.right.circle") {
                            ForEach(upcoming.prefix(3)) { placement in
                                stepLine(placement, detail: "in \(placement.start - minute) Min.")
                            }
                        }
                    }
                    if !unattended.isEmpty {
                        section("Läuft von allein", systemImage: "flame") {
                            ForEach(unattended) { placement in
                                stepLine(placement, detail: "noch \(placement.end - minute) Min.")
                            }
                        }
                    }
                    if !done.isEmpty {
                        section("Erledigt", systemImage: "checkmark.circle") {
                            Text("\(done.count) von \(placements.count) Schritten")
                                .font(Theme.bodyFont(14))
                                .foregroundColor(Theme.subtitle)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func clock(remaining: Int, minute: Int) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: String(format: "%d:%02d", remaining / 60, remaining % 60))
                .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(remaining > 0 ? Theme.title : Theme.good)
            Text("Minute \(min(minute, plan.schedule.makespan)) von \(plan.schedule.makespan)")
                .font(Theme.bodyFont(14))
                .foregroundColor(Theme.subtitle)
            if let budget = plan.schedule.budget, plan.schedule.makespan > budget {
                Text("Budget \(budget) Minuten, Plan \(plan.schedule.makespan)")
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.warning)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func section<Content: View>(_ title: LocalizedStringKey, systemImage: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(Theme.bodyFont(16).weight(.semibold))
                .foregroundColor(Theme.cardTitle)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func stepLine(_ placement: KitchenPlacement, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: placement.task.name)
                    .font(Theme.bodyFont(15))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if !placement.task.component.isEmpty {
                    Text(verbatim: placement.task.component)
                        .font(Theme.bodyFont(12))
                        .foregroundColor(Theme.subtitle)
                }
            }
            Spacer()
            Text(detail)
                .font(Theme.bodyFont(13).monospacedDigit())
                .foregroundColor(Theme.accentText)
        }
    }
}
