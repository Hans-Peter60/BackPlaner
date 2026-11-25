//
//  CookModeView.swift
//  CookPlanner
//
//  The plan run against the clock: a countdown, what the hands do now,
//  what comes next, what runs on its own. The cook ticks off each hands-on
//  step; done early or late, the rest of the plan is placed afresh from
//  that moment (KitchenScheduler.replan). A step with an unattended part is
//  ticked twice: once when the hands are done — the pot is on — and it
//  runs its time from there; once when it is taken off, or the clock ends
//  it. Reminders (CookReminders) and the Live Activity (CookActivityManager)
//  follow the live plan, so the phone may be locked in between. Every
//  change goes to CookRunState, so a run survives the app being ended.
//

import BakePlannerCore
import SwiftUI
import UIKit

struct CookModeView: View {

    let plan: DishPlan

    init(plan: DishPlan) {
        self.plan = plan
    }

    /// The run the last launch left under way, continued where it was.
    init(plan: DishPlan, restoring state: CookRunState) {
        self.plan = plan
        _startedAt = State(initialValue: state.startedAt)
        _pausedAt = State(initialValue: state.pausedAt)
        _pausedSeconds = State(initialValue: state.pausedSeconds)
        _finished = State(initialValue: state.finished)
        _handsDone = State(initialValue: state.handsDone)
        _tickHistory = State(initialValue: state.ticks)
        _doneSeconds = State(initialValue: state.doneSeconds)
        _handsDoneSeconds = State(initialValue: state.handsDoneSeconds)
        _startSeconds = State(initialValue: state.startSeconds)
    }

    #if DEBUG
    /// For screenshots: the clock started `seconds` ago, the steps due by
    /// then ticked off (-CookSample).
    init(plan: DishPlan, startedSecondsAgo seconds: TimeInterval) {
        self.plan = plan
        _startedAt = State(initialValue: Date.now.addingTimeInterval(-seconds))
        let minute = Int(seconds) / 60
        _finished = State(initialValue: Dictionary(uniqueKeysWithValues: plan.schedule.placements
            .filter { $0.end <= minute }.map { ($0.id, $0.end) }))
    }
    #endif

    @Environment(\.dismiss) private var dismiss
    /// Wide (iPad, unfolded Duo): the device stands further away, the
    /// current step grows further.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var startedAt: Date?
    /// While paused, when the pause began; the clock stands still.
    @State private var pausedAt: Date?
    /// Seconds spent in earlier pauses, taken off the clock.
    @State private var pausedSeconds: TimeInterval = 0
    /// The steps ticked off, with the minute each was done.
    @State private var finished: [String: Int] = [:]
    /// Pots and oven steps whose hands-on part is done, with the minute:
    /// they run on their own from there.
    @State private var handsDone: [String: Int] = [:]
    /// The ticks in order, for taking the last one back.
    @State private var tickHistory: [CookRunState.Tick] = []
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
    @State private var handsDoneSeconds: [String: Int] = [:]
    @State private var startSeconds: [String: Int] = [:]
    @State private var runSaved = false
    /// Neither reminders nor alarms may be shown: the cook should know
    /// before locking the phone.
    @State private var silenced = false
    @State private var confirmingEnd = false
    @State private var showingTimeline = false
    @AppStorage(CookSettings.clockModeKey) private var clockMode = CookClockMode.challenge

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
            .sheet(isPresented: $showingTimeline) {
                NavigationStack {
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        ScrollView {
                            PlanTimelineView(layout: KitchenTimelineLayout(schedule: live ?? plan.schedule,
                                                                           components: plan.dish.components),
                                             now: startedAt == nil ? nil : Double(elapsedSeconds(at: context.date)) / 60,
                                             finished: Set(finished.keys))
                                .padding()
                        }
                    }
                    .navigationTitle("Zeitachse")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fertig") { showingTimeline = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            // The phone lies on the counter while the hands are busy: the
            // screen stays on as long as the cook mode is open.
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                CookReminders.shared.cancelAll()
                CookAlarms.shared.cancelAll()
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
                        if hasRecord {
                            Button("Beenden und Protokoll sichern") { end(keepingRecord: true) }
                        }
                        if hasRecord {
                            Button("Beenden ohne Protokoll", role: .destructive) { end(keepingRecord: false) }
                        } else {
                            Button("Beenden", role: .destructive) { end(keepingRecord: false) }
                        }
                        Button("Weiterkochen", role: .cancel) { }
                    } message: {
                        if hasRecord {
                            Text("Das Protokoll hält fest, wann jeder Schritt erledigt war.")
                        } else {
                            Text("Noch ist kein Schritt erledigt; es gibt nichts festzuhalten.")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingTimeline = true
                    } label: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                    .accessibilityLabel("Zeitachse")
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
                                CookAlarms.shared.cancelAll()
                                remindersSignature = ""
                                syncActivity(minute: elapsedSeconds(at: .now) / 60)
                                persist()
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
        persist()
    }

    /// Keeps the run as it stands, so the next launch can take it up again.
    private func persist() {
        guard let startedAt else { return }
        CookRunState(dishID: plan.dish.id, startedAt: startedAt, pausedAt: pausedAt, pausedSeconds: pausedSeconds,
                     finished: finished, handsDone: handsDone, ticks: tickHistory, doneSeconds: doneSeconds,
                     handsDoneSeconds: handsDoneSeconds, startSeconds: startSeconds).save()
    }

    /// The stopwatch second the hands were last free: the latest tick of a
    /// hands-only step, or the latest "pot is on" tick.
    private var lastHandsFreeSecond: Int {
        let handsOnly = doneSeconds.filter { key, _ in
            plan.dish.tasks.first { $0.id == key }.map { $0.handsMinutes > 0 && $0.unattendedMinutes == 0 } ?? false
        }.values.max() ?? 0
        return max(handsOnly, handsDoneSeconds.values.max() ?? 0)
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
                    && handsDone[placement.id] == nil
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
        // Whole seconds from the clock's start, so a refresh without a
        // change finds the same state and sends no update.
        let state = CookActivityAttributes.ContentState(
            finishDate: clockStart.addingTimeInterval(TimeInterval(schedule.makespan * 60)),
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
        let clockStart = startedAt.addingTimeInterval(pausedSeconds)
        CookAlarms.shared.sync(schedule: schedule, finished: Set(finished.keys), minute: minute,
                               clockStart: clockStart, dishName: plan.dish.name)
        CookReminders.shared.sync(schedule: schedule, finished: Set(finished.keys), minute: minute,
                                  clockStart: clockStart, dishName: plan.dish.name,
                                  ringing: CookAlarms.shared.alarmTasks(in: schedule, finished: Set(finished.keys),
                                                                       minute: minute))
    }

    /// Takes the last tick back: the step is in the cook's hands again — or
    /// on its burner — and the plan is continued without it. A "pot is on"
    /// tick taken back puts the pot back into the cook's hands, overdue if
    /// its hands-on minutes have passed; it cooks again only with the tick.
    private func undoLastTick() {
        guard let tick = tickHistory.popLast() else { return }
        switch tick.kind {
        case .done:
            finished[tick.id] = nil
            doneSeconds[tick.id] = nil
            if handsDone[tick.id] == nil { startSeconds[tick.id] = nil }
        case .hands:
            handsDone[tick.id] = nil
            handsDoneSeconds[tick.id] = nil
            startSeconds[tick.id] = nil
        }
        replan(minute: elapsedSeconds(at: .now) / 60)
        persist()
    }

    /// Continues the live plan from `minute` around what has been ticked off.
    private func replan(minute: Int) {
        guard startedAt != nil else { return }
        let previous = live ?? plan.schedule
        live = (try? KitchenScheduler.replan(plan.dish.tasks, kitchen: plan.schedule.kitchen, budget: plan.schedule.budget,
                                             previous: previous,
                                             progress: KitchenProgress(now: minute, finished: finished, handsDone: handsDone))) ?? previous
        syncReminders(minute: minute)
        syncActivity(minute: minute)
    }

    /// The step is done. A hands-only step begins when the hands were last
    /// free — at the previous hands-on tick, if that came later than the
    /// plan's minute; the live plan only knows whole minutes.
    private func tickOff(_ id: String, minute: Int) {
        let second = elapsedSeconds(at: .now)
        let placement = (live ?? plan.schedule).placement(of: id)
        if startSeconds[id] == nil {
            var start = (placement?.start ?? 0) * 60
            if (placement?.task.handsMinutes ?? 0) > 0 { start = max(start, lastHandsFreeSecond) }
            startSeconds[id] = min(second, start)
        }
        doneSeconds[id] = second
        finished[id] = minute
        tickHistory.append(.init(id: id, kind: .done))
        replan(minute: minute)
        persist()
    }

    /// The hands are done with a pot or oven step: it runs on its own from
    /// now, for its unattended time, and is ticked off — or ended by the
    /// clock — later. Ticking it off here instead would have thrown its
    /// cooking time away.
    private func putOn(_ id: String, minute: Int) {
        let second = elapsedSeconds(at: .now)
        let placement = (live ?? plan.schedule).placement(of: id)
        let start = max((placement?.start ?? 0) * 60, lastHandsFreeSecond)
        startSeconds[id] = min(second, start)
        handsDoneSeconds[id] = second
        handsDone[id] = minute
        tickHistory.append(.init(id: id, kind: .hands))
        replan(minute: minute)
        persist()
    }

    private func end(keepingRecord: Bool) {
        CookReminders.shared.cancelAll()
        CookAlarms.shared.cancelAll()
        CookActivityManager.shared.endAll()
        if keepingRecord { saveRun() } else { runSaved = true }
        CookRunState.clear()
        dismiss()
    }

    /// Whether a record would hold anything: a tick, a flame, or a pot
    /// that ran its time.
    private var hasRecord: Bool {
        guard startedAt != nil else { return false }
        if !doneSeconds.isEmpty || !handsDoneSeconds.isEmpty { return true }
        let minute = elapsedSeconds(at: .now) / 60
        return (live ?? plan.schedule).placements.contains {
            ($0.task.unattendedMinutes > 0 || $0.task.handsMinutes == 0) && $0.end <= minute
        }
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
                                   startedSecond: startSeconds[task.id] ?? placement.start * 60, doneSecond: placement.end * 60,
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
                && handsDone[placement.id] == nil
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
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Uhr", selection: $clockMode) {
                            ForEach(CookClockMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(clockMode == .challenge
                             ? "Die Uhr zählt das Zeitbudget rückwärts, wie in der Sendung."
                             : "Die Uhr läuft ab 0:00 – so lernst Du, wie lange das Gericht wirklich dauert.")
                            .font(Theme.bodyFont(13))
                            .foregroundColor(Theme.subtitle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        startedAt = .now
                        persist()
                        // The banners of the last run go before this one's come.
                        CookReminders.shared.cancelAll()
                        Task {
                            let reminders = await CookReminders.shared.requestAuthorization()
                            let alarms = await CookAlarms.shared.requestAuthorization()
                            silenced = !reminders && !alarms
                            // The prompts may have taken a minute: the plan has
                            // moved on and may have been scheduled without
                            // alarms meanwhile — schedule afresh from now.
                            remindersSignature = ""
                            let minute = self.elapsedSeconds(at: .now) / 60
                            syncReminders(minute: minute)
                            syncActivity(minute: minute)
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
                                    .font(Theme.bodyFont(24).weight(.semibold))
                                    .foregroundColor(Theme.subtitle)
                            } else if doneCount == placements.count {
                                Text("Fertig, anrichten!")
                                    .font(Theme.bodyFont(28).weight(.semibold))
                                    .foregroundColor(Theme.good)
                            }
                        }
                        ForEach(handsNow) { placement in
                            let overdue = minute >= placement.start + placement.task.handsMinutes
                            let pot = placement.task.unattendedMinutes > 0
                            stepLine(placement, ingredients: plan.dish.ingredients(for: placement.task),
                                     detail: overdue ? "überfällig" : "noch \(placement.start + placement.task.handsMinutes - minute) Min.",
                                     emphasis: overdue, large: true,
                                     doneLabel: pot ? "Steht, läuft von allein" : "Schritt erledigt") {
                                if pot {
                                    putOn(placement.id, minute: minute)
                                } else {
                                    tickOff(placement.id, minute: minute)
                                }
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
                            ForEach(Array(tickHistory.reversed().enumerated()), id: \.offset) { _, tick in
                                let second = tick.kind == .done ? doneSeconds[tick.id] : handsDoneSeconds[tick.id]
                                if let second, let task = plan.dish.tasks.first(where: { $0.id == tick.id }) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(verbatim: task.name)
                                            .font(Theme.bodyFont(13))
                                            .foregroundColor(Theme.cardTitle)
                                            .lineLimit(2)
                                        if tick.kind == .hands {
                                            Image(systemName: "flame")
                                                .font(Theme.bodyFont(11))
                                                .foregroundColor(Theme.subtitle)
                                                .accessibilityLabel("steht, läuft von allein")
                                        }
                                        Spacer()
                                        Text(verbatim: KitchenCookRun.clockText(second))
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
            if silenced {
                Label("Mitteilungen und Wecker sind aus – gesperrt bleibt das iPhone still. Einschalten unter Einstellungen → CookPlanner.",
                      systemImage: "bell.slash")
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.warning)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if clockMode == .challenge {
                // The countdown: the time budget (or the plan, without one)
                // running out, and on into the minus.
                let target = (plan.schedule.budget ?? live.makespan) * 60
                let left = target - elapsed
                Text(verbatim: left >= 0 ? KitchenCookRun.clockText(left) : "−" + KitchenCookRun.clockText(-left))
                    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(left < 0 ? Theme.danger : left <= 60 ? Theme.warning : Theme.title)
                if left >= 0 {
                    Text("Budget \(target / 60) Min. · Plan fertig in Minute \(live.makespan)")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.subtitle)
                } else {
                    Text("Zeit um – \(KitchenCookRun.clockText(-left)) drüber")
                        .font(Theme.bodyFont(14).weight(.semibold))
                        .foregroundColor(Theme.danger)
                }
            } else {
                // The stopwatch: it counts up from the start, pauses not counted.
                Text(verbatim: KitchenCookRun.clockText(elapsed))
                    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(Theme.title)
            }
            if clockMode == .challenge {
                EmptyView()
            } else if remaining > 0 {
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

    /// A step. `large` is for what is in the hands right now: read from
    /// across the kitchen, with wet or busy hands — the name at twice the
    /// size, the time left and the ingredients clearly, and a check mark
    /// big enough to hit with a knuckle.
    @ViewBuilder
    private func stepLine(_ placement: KitchenPlacement, ingredients: [KitchenIngredient] = [],
                          detail: LocalizedStringKey, emphasis: Bool = false, large: Bool = false,
                          doneLabel: LocalizedStringKey = "Schritt erledigt",
                          onDone: (() -> Void)? = nil) -> some View {
        if large {
            let wide = sizeClass == .regular
            VStack(alignment: .leading, spacing: wide ? 12 : 8) {
                Text(verbatim: placement.task.name)
                    .font(Theme.bodyFont(wide ? 42 : 30).weight(.semibold))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if !ingredients.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "basket")
                            .accessibilityHidden(true)
                        Text(verbatim: ingredients.map { $0.line() }.joined(separator: " · "))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Theme.bodyFont(wide ? 26 : 20))
                    .foregroundColor(Theme.cardTitle)
                }
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail)
                            .font(Theme.bodyFont(wide ? 26 : 20).weight(.semibold).monospacedDigit())
                            .foregroundColor(emphasis ? Theme.danger : Theme.accentText)
                        HStack(spacing: 6) {
                            if !placement.task.component.isEmpty {
                                Text(verbatim: placement.task.component)
                            }
                            if let temperature = placement.task.ovenTemperature {
                                Text("Ofen \(temperature) °C")
                            }
                        }
                        .font(Theme.bodyFont(16))
                        .foregroundColor(Theme.subtitle)
                    }
                    Spacer(minLength: 8)
                    if let onDone {
                        Button(action: onDone) {
                            Image(systemName: placement.task.unattendedMinutes > 0 ? "flame.circle.fill" : "checkmark.circle.fill")
                                .font(.system(size: wide ? 64 : 52))
                                .foregroundColor(Theme.accentText)
                                .frame(width: wide ? 88 : 72, height: wide ? 88 : 72)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(doneLabel)
                    }
                }
            }
            .padding(.vertical, 4)
        } else {
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
}
