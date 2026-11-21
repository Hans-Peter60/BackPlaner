//
//  CookModeView.swift
//  CookPlanner
//
//  The plan run against the clock: a countdown, what the hands do now,
//  what comes next, what runs on its own. The cook ticks off each hands-on
//  step; done early or late, the rest of the plan is placed afresh from
//  that moment (KitchenScheduler.replan). Steps with an unattended part
//  end by the clock and may be ticked off early. Reminders (CookReminders)
//  and the Live Activity (CookActivityManager) follow the live plan, so
//  the phone may be locked in between.
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
    /// What the reminders were last scheduled for, to spare the rescheduling
    /// when a minute passes without a change.
    @State private var remindersSignature = ""
    /// The stopwatch second each ticked step was done, and the second the
    /// live plan had it begin — the record kept when cooking ends.
    @State private var doneSeconds: [String: Int] = [:]
    @State private var startSeconds: [String: Int] = [:]
    @State private var runSaved = false
    @State private var confirmingEnd = false

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
            .onDisappear {
                CookReminders.shared.cancelAll()
                CookActivityManager.shared.endAll()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Beenden") {
                        if startedAt == nil {
                            end(keepingRecord: false)
                        } else {
                            confirmingEnd = true
                        }
                    }
                    // An alert, not a confirmation dialog: on the iPhone the
                    // dialog came as a popover without "Weiterkochen".
                    .alert("Kochen beenden?", isPresented: $confirmingEnd) {
                        Button("Beenden und Protokoll sichern") { end(keepingRecord: true) }
                        Button("Beenden ohne Protokoll", role: .destructive) { end(keepingRecord: false) }
                        Button("Weiterkochen", role: .cancel) { }
                    } message: {
                        Text("Das Protokoll hält fest, wann jeder Schritt erledigt war.")
                    }
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
                                CookReminders.shared.cancelAll()
                                remindersSignature = ""
                                syncActivity(minute: elapsedSeconds(at: .now) / 60)
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
        let minute = elapsedSeconds(at: .now) / 60
        syncReminders(minute: minute)
        syncActivity(minute: minute)
    }

    /// The Live Activity for the live plan as it stands.
    private func syncActivity(minute: Int) {
        guard let startedAt else { return }
        let now = Date.now
        let schedule = live ?? plan.schedule
        let placements = schedule.placements
        let clockStart = startedAt.addingTimeInterval(pausedSeconds)
        let current = placements
            .filter { placement in
                placement.task.handsMinutes > 0 && placement.start <= minute && finished[placement.id] == nil
                    && (placement.task.unattendedMinutes == 0 || minute < placement.handsEnd)
            }
            .min { ($0.start, $0.task.id) < ($1.start, $1.task.id) }
        let next = placements
            .filter { $0.task.handsMinutes > 0 && $0.start > minute && finished[$0.id] == nil }
            .min { ($0.start, $0.task.id) < ($1.start, $1.task.id) }
        let running = placements.filter { placement in
            placement.task.unattendedMinutes > 0 && placement.handsEnd <= minute && minute < placement.end
                && finished[placement.id] == nil
        }.count
        let done = placements.filter { placement in
            finished[placement.id] != nil
                || ((placement.task.unattendedMinutes > 0 || placement.task.handsMinutes == 0) && placement.end <= minute)
        }.count
        let remaining = max(0, schedule.makespan * 60 - elapsedSeconds(at: now))
        let state = CookActivityAttributes.ContentState(
            finishDate: pausedAt == nil ? now.addingTimeInterval(TimeInterval(remaining)) : clockStart.addingTimeInterval(TimeInterval(schedule.makespan * 60)),
            currentStep: current?.task.name,
            currentComponent: current.map { $0.task.component.isEmpty ? nil : $0.task.component } ?? nil,
            nextStep: next?.task.name,
            nextDate: next.map { clockStart.addingTimeInterval(TimeInterval($0.start * 60)) },
            runningCount: running,
            doneCount: done,
            totalCount: placements.count,
            isPaused: pausedAt != nil,
            pausedRemainingMinutes: (remaining + 59) / 60)
        CookActivityManager.shared.refresh(dishName: plan.dish.name, state: state, now: now)
    }

    /// The reminders for the live plan as it stands, unless nothing changed.
    private func syncReminders(minute: Int) {
        guard let startedAt, pausedAt == nil else { return }
        let schedule = live ?? plan.schedule
        let signature = schedule.placements.map { "\($0.id):\($0.start)-\($0.end)" }.joined(separator: ",")
            + "|" + finished.keys.sorted().joined(separator: ",") + "|\(Int(pausedSeconds))"
        guard signature != remindersSignature else { return }
        remindersSignature = signature
        CookReminders.shared.sync(schedule: schedule, finished: Set(finished.keys), minute: minute,
                                  clockStart: startedAt.addingTimeInterval(pausedSeconds), dishName: plan.dish.name)
    }

    /// Takes the last tick back: the step is in the cook's hands again — or
    /// on its burner — and the plan is continued without it.
    private func undoLastTick() {
        guard let id = tickHistory.popLast() else { return }
        finished[id] = nil
        doneSeconds[id] = nil
        startSeconds[id] = nil
        replan(minute: elapsedSeconds(at: .now) / 60)
    }

    /// Continues the live plan from `minute` around what has been ticked off.
    private func replan(minute: Int) {
        guard startedAt != nil else { return }
        let previous = live ?? plan.schedule
        live = (try? KitchenScheduler.replan(plan.dish.tasks, kitchen: plan.schedule.kitchen, budget: plan.schedule.budget,
                                             previous: previous,
                                             progress: KitchenProgress(now: minute, finished: finished))) ?? previous
        syncReminders(minute: minute)
        syncActivity(minute: minute)
    }

    private func tickOff(_ id: String, minute: Int) {
        let second = elapsedSeconds(at: .now)
        let placement = (live ?? plan.schedule).placement(of: id)
        var start = (placement?.start ?? 0) * 60
        // A hands-on step begins when the hands were last free: at the
        // previous hands-on tick, if that came later than the plan's
        // minute — the live plan only knows whole minutes.
        if (placement?.task.handsMinutes ?? 0) > 0 {
            let handsTicks = doneSeconds.filter { key, _ in
                (plan.dish.tasks.first { $0.id == key }?.handsMinutes ?? 0) > 0
            }.values
            start = max(start, handsTicks.max() ?? 0)
        }
        doneSeconds[id] = second
        startSeconds[id] = min(second, start)
        finished[id] = minute
        tickHistory.append(id)
        replan(minute: minute)
    }

    private func end(keepingRecord: Bool) {
        CookReminders.shared.cancelAll()
        CookActivityManager.shared.endAll()
        if keepingRecord { saveRun() } else { runSaved = true }
        dismiss()
    }

    /// Keeps the stopwatch record: every ticked step with its seconds, and
    /// the pots and waits that ran their time without a tick. Nothing is
    /// kept when cooking never started or nothing was done.
    private func saveRun() {
        guard !runSaved, let startedAt else { return }
        runSaved = true
        let total = elapsedSeconds(at: .now)
        let minute = total / 60
        let schedule = live ?? plan.schedule
        var steps = [KitchenCookRun.Step]()
        for placement in schedule.placements {
            let task = placement.task
            let planned = plan.schedule.placement(of: task.id)?.start ?? placement.start
            if let done = doneSeconds[task.id] {
                steps.append(.init(taskID: task.id, name: task.name, component: task.component,
                                   plannedMinutes: task.minutes, plannedStart: planned,
                                   startedSecond: startSeconds[task.id] ?? placement.start * 60,
                                   doneSecond: done, tickedByCook: true))
            } else if (task.unattendedMinutes > 0 || task.handsMinutes == 0), placement.end <= minute {
                steps.append(.init(taskID: task.id, name: task.name, component: task.component,
                                   plannedMinutes: task.minutes, plannedStart: planned,
                                   startedSecond: placement.start * 60, doneSecond: placement.end * 60,
                                   tickedByCook: false))
            }
        }
        guard !steps.isEmpty else { return }
        CookRunLog.shared.add(KitchenCookRun(dishID: plan.dish.id, dishName: plan.dish.name, startedAt: startedAt,
                                             totalSeconds: total, plannedMinutes: plan.schedule.makespan,
                                             steps: steps, totalSteps: schedule.placements.count))
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
                clock(elapsed: elapsedSeconds, remaining: remaining, minute: minute, live: live)

                if startedAt == nil {
                    Button {
                        startedAt = .now
                        Task {
                            _ = await CookReminders.shared.requestAuthorization()
                            syncReminders(minute: 0)
                            syncActivity(minute: 0)
                        }
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
                            stepLine(placement, ingredients: plan.dish.ingredients(for: placement.task),
                                     detail: overdue ? "überfällig" : "noch \(placement.start + placement.task.handsMinutes - minute) Min.",
                                     emphasis: overdue) {
                                tickOff(placement.id, minute: minute)
                            }
                        }
                    }
                    if !upcoming.isEmpty {
                        section("Gleich", systemImage: "arrow.right.circle") {
                            ForEach(upcoming.prefix(3)) { placement in
                                stepLine(placement, ingredients: plan.dish.ingredients(for: placement.task),
                                         detail: "in \(placement.start - minute) Min.")
                            }
                        }
                    }
                    if !unattended.isEmpty {
                        section("Läuft von allein", systemImage: "flame") {
                            ForEach(unattended) { placement in
                                stepLine(placement, detail: unattendedDetail(placement, minute: minute)) {
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
                            // What the stopwatch said at each tick, latest first.
                            ForEach(tickHistory.reversed(), id: \.self) { id in
                                if let done = doneSeconds[id], let task = plan.dish.tasks.first(where: { $0.id == id }) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(verbatim: task.name)
                                            .font(Theme.bodyFont(13))
                                            .foregroundColor(Theme.cardTitle)
                                            .lineLimit(2)
                                        Spacer()
                                        Text(verbatim: KitchenCookRun.clockText(done))
                                            .font(Theme.bodyFont(13).monospacedDigit())
                                            .foregroundColor(Theme.accentText)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    /// "noch 4 Min." — or, for a step with a window, "noch 2–7 Min." and,
    /// once the planned end has passed, "bis zu 5 Min.".
    private func unattendedDetail(_ placement: KitchenPlacement, minute: Int) -> LocalizedStringKey {
        guard let window = placement.task.unattendedWindow else {
            return "noch \(placement.end - minute) Min."
        }
        let earliest = placement.start + placement.task.handsMinutes + window.lowerBound
        let latest = placement.start + placement.task.handsMinutes + window.upperBound
        if minute < earliest {
            return "noch \(earliest - minute)–\(latest - minute) Min."
        }
        return "bis zu \(max(0, latest - minute)) Min."
    }

    private func clock(elapsed: Int, remaining: Int, minute: Int, live: KitchenSchedule) -> some View {
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
            // The stopwatch: it counts up from the start, pauses not counted.
            Text(verbatim: KitchenCookRun.clockText(elapsed))
                .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(Theme.title)
            if remaining > 0 {
                Text("Plan \(live.makespan) Min. · noch \(KitchenCookRun.clockText(remaining))")
                    .font(Theme.bodyFont(14))
                    .foregroundColor(Theme.subtitle)
            } else {
                Text("\(KitchenCookRun.clockText(elapsed - live.makespan * 60)) über dem Plan von \(live.makespan) Min.")
                    .font(Theme.bodyFont(14))
                    .foregroundColor(elapsed > live.makespan * 60 ? Theme.warning : Theme.good)
            }
            if live.makespan > plan.schedule.makespan {
                Text("Fertig in Minute \(live.makespan), \(live.makespan - plan.schedule.makespan) Min. später als geplant")
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.warning)
            } else if live.makespan < plan.schedule.makespan {
                Text("Fertig in Minute \(live.makespan), \(plan.schedule.makespan - live.makespan) Min. früher als geplant")
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

    private func stepLine(_ placement: KitchenPlacement, ingredients: [KitchenIngredient] = [],
                          detail: LocalizedStringKey, emphasis: Bool = false,
                          onDone: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: placement.task.name)
                    .font(Theme.bodyFont(15))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                // What to have at hand for the step, as the recipe lists it.
                if !ingredients.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "basket")
                            .accessibilityHidden(true)
                        Text(verbatim: ingredients.map { $0.line() }.joined(separator: " · "))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.cardTitle)
                    .padding(.vertical, 1)
                }
                HStack(spacing: 6) {
                    if !placement.task.component.isEmpty {
                        Text(verbatim: placement.task.component)
                    }
                    if let temperature = placement.task.ovenTemperature {
                        Text("Ofen \(temperature) °C")
                    }
                }
                .font(Theme.bodyFont(12))
                .foregroundColor(Theme.subtitle)
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
