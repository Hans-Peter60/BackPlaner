//
//  CookModeView.swift
//  CookPlanner
//
//  The plan run against the clock: a countdown, what the hands do now,
//  what comes next, what runs on its own. The cook ticks off each hands-on
//  step; done early or late, the rest of the plan is placed afresh from
//  that moment (KitchenScheduler.replan). Steps with an unattended part
//  end by the clock and may be ticked off early.
//

import BakePlannerCore
import SwiftUI

struct CookModeView: View {

    let plan: DishPlan

    @Environment(\.dismiss) private var dismiss
    @State private var startedAt: Date?
    /// While paused, when the pause began; the clock stands still.
    @State private var pausedAt: Date?
    /// Seconds spent in earlier pauses, taken off the clock.
    @State private var pausedSeconds: TimeInterval = 0
    /// The steps ticked off, with the minute each was done.
    @State private var finished: [String: Int] = [:]
    /// The ticks in order, for taking the last one back.
    @State private var tickHistory: [String] = []
    /// The plan as it stands: continued every minute and at every tick-off
    /// from the previous live plan, so that a step pulled forward stays
    /// where it began instead of being placed afresh each minute.
    @State private var live: KitchenSchedule?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = elapsedSeconds(at: context.date)
                content(elapsedSeconds: seconds)
                    .task(id: seconds / 60) { replan(minute: seconds / 60) }
            }
            .warmBackground()
            .navigationTitle("Kochen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Beenden") { dismiss() }
                }
                if startedAt != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            undoLastTick()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .disabled(tickHistory.isEmpty)
                        .accessibilityLabel("Rückgängig")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if pausedAt == nil {
                            Button {
                                pausedAt = .now
                            } label: {
                                Image(systemName: "pause.fill")
                            }
                            .accessibilityLabel("Pause")
                        } else {
                            Button {
                                resume()
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .accessibilityLabel("Weiter")
                        }
                    }
                }
            }
        }
    }

    /// Seconds on the cooking clock: since the start, less the pauses; a
    /// running pause holds the clock where it stopped.
    private func elapsedSeconds(at date: Date) -> Int {
        guard let startedAt else { return 0 }
        let end = pausedAt ?? date
        return max(0, Int(end.timeIntervalSince(startedAt) - pausedSeconds))
    }

    private func resume() {
        guard let pausedAt else { return }
        pausedSeconds += Date.now.timeIntervalSince(pausedAt)
        self.pausedAt = nil
    }

    /// Takes the last tick back: the step is in the cook's hands again — or
    /// on its burner — and the plan is continued without it.
    private func undoLastTick() {
        guard let id = tickHistory.popLast() else { return }
        finished[id] = nil
        replan(minute: elapsedSeconds(at: .now) / 60)
    }

    /// Continues the live plan from `minute` around what has been ticked off.
    private func replan(minute: Int) {
        guard startedAt != nil else { return }
        let previous = live ?? plan.schedule
        live = (try? KitchenScheduler.replan(plan.dish.tasks, kitchen: plan.schedule.kitchen, budget: plan.schedule.budget,
                                             previous: previous,
                                             progress: KitchenProgress(now: minute, finished: finished))) ?? previous
    }

    private func tickOff(_ id: String, minute: Int) {
        finished[id] = minute
        tickHistory.append(id)
        replan(minute: minute)
    }

    private func content(elapsedSeconds: Int) -> some View {
        let minute = elapsedSeconds / 60
        let live = self.live ?? plan.schedule
        let placements = live.placements
        // In the hands: begun, not ticked off, and — with an unattended
        // part — still in its hands-on minutes.
        let handsNow = placements.filter { placement in
            placement.task.handsMinutes > 0 && placement.start <= minute && finished[placement.id] == nil
                && (placement.task.unattendedMinutes == 0 || minute < placement.handsEnd)
        }
        let unattended = placements.filter { placement in
            placement.task.unattendedMinutes > 0 && placement.handsEnd <= minute && minute < placement.end
                && finished[placement.id] == nil
        }
        let upcoming = placements.filter { $0.start > minute }.sorted { ($0.start, $0.task.id) < ($1.start, $1.task.id) }
        let doneCount = placements.filter { placement in
            finished[placement.id] != nil
                || ((placement.task.unattendedMinutes > 0 || placement.task.handsMinutes == 0) && placement.end <= minute)
        }.count
        let remaining = max(0, live.makespan * 60 - elapsedSeconds)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                clock(remaining: remaining, minute: minute, live: live)

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
                            } else if doneCount == placements.count {
                                Text("Fertig, anrichten!")
                                    .font(Theme.bodyFont(15))
                                    .foregroundColor(Theme.good)
                            }
                        }
                        ForEach(handsNow) { placement in
                            let overdue = minute >= placement.start + placement.task.handsMinutes
                            stepLine(placement,
                                     detail: overdue ? "überfällig" : "noch \(placement.start + placement.task.handsMinutes - minute) Min.",
                                     emphasis: overdue) {
                                tickOff(placement.id, minute: minute)
                            }
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
                                stepLine(placement, detail: "noch \(placement.end - minute) Min.") {
                                    tickOff(placement.id, minute: minute)
                                }
                            }
                        }
                    }
                    if doneCount > 0 {
                        section("Erledigt", systemImage: "checkmark.circle") {
                            Text("\(doneCount) von \(placements.count) Schritten")
                                .font(Theme.bodyFont(14))
                                .foregroundColor(Theme.subtitle)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func clock(remaining: Int, minute: Int, live: KitchenSchedule) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: plan.dish.name)
                .font(Theme.bodyFont(14))
                .foregroundColor(Theme.subtitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if pausedAt != nil {
                Label("Pause, die Uhr steht", systemImage: "pause.circle.fill")
                    .font(Theme.bodyFont(14).weight(.semibold))
                    .foregroundColor(Theme.warning)
            }
            Text(verbatim: String(format: "%d:%02d", remaining / 60, remaining % 60))
                .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(remaining > 0 ? Theme.title : Theme.good)
            Text("Minute \(min(minute, live.makespan)) von \(live.makespan)")
                .font(Theme.bodyFont(14))
                .foregroundColor(Theme.subtitle)
            if live.makespan > plan.schedule.makespan {
                Text("Fertig in Minute \(live.makespan), \(live.makespan - plan.schedule.makespan) Minuten später als geplant")
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.warning)
            } else if live.makespan < plan.schedule.makespan {
                Text("Fertig in Minute \(live.makespan), \(plan.schedule.makespan - live.makespan) Minuten früher als geplant")
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.good)
            } else if let budget = plan.schedule.budget, plan.schedule.makespan > budget {
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

    private func stepLine(_ placement: KitchenPlacement, detail: LocalizedStringKey, emphasis: Bool = false,
                          onDone: (() -> Void)? = nil) -> some View {
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
                .foregroundColor(emphasis ? Theme.danger : Theme.accentText)
            if let onDone {
                Button(action: onDone) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24))
                        .foregroundColor(Theme.accentText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Schritt erledigt")
            }
        }
    }
}
