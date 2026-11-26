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
        _revision = State(initialValue: state.revision ?? 0)
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
    /// Reads each step that comes into the hands and each pot that is done
    /// aloud on its own, for the cook whose eyes are on the pan.
    @AppStorage(CookSettings.readAloudKey) private var readAloud = false
    @State private var speaker = StepSpeaker()
    /// Listens for "Erledigt", "Steht", "Vorlesen" and the rest.
    @State private var voice = CookVoiceListener()
    /// What was read aloud already, so a step is announced once.
    @State private var announcedSteps: Set<String> = []
    @State private var announcedEnds: Set<String> = []
    /// The saved state's revision this view wrote or adopted last.
    @State private var revision = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

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
                speaker.stop()
                stopVoice()
                CookReminders.shared.cancelAll()
                CookAlarms.shared.cancelAll()
                CookActivityManager.shared.endAll()
            }
            // The microphone is dropped while the app talks, and a moment
            // after, so the room's echo of its own voice is not taken for a
            // command.
            .onChange(of: speaker.isSpeaking) { _, speaking in
                if speaking {
                    voice.isMuted = true
                } else {
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        if !speaker.isSpeaking { voice.isMuted = false }
                    }
                }
            }
            // In the background the microphone is of no use and the audio
            // session would hold the phone's audio.
            .onChange(of: scenePhase) { _, phase in
                if phase != .active, voice.isActive { stopVoice() }
                if phase == .active { adoptExternalChanges() }
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
                                pause()
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

    private func pause() {
        guard startedAt != nil, pausedAt == nil else { return }
        pausedAt = .now
        CookReminders.shared.cancelAll()
        CookAlarms.shared.cancelAll()
        remindersSignature = ""
        syncActivity(minute: elapsedSeconds(at: .now) / 60)
        persist()
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
        revision += 1
        CookRunState(dishID: plan.dish.id, startedAt: startedAt, pausedAt: pausedAt, pausedSeconds: pausedSeconds,
                     finished: finished, handsDone: handsDone, ticks: tickHistory, doneSeconds: doneSeconds,
                     handsDoneSeconds: handsDoneSeconds, startSeconds: startSeconds, revision: revision).save()
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
        var run = KitchenCookRun(dishID: plan.dish.id, dishName: plan.dish.name, startedAt: startedAt,
                                 totalSeconds: total, plannedMinutes: plan.schedule.makespan,
                                 steps: steps, totalSteps: schedule.placements.count)
        if clockMode == .relaxed { run.relaxed = true }
        CookRunLog.shared.add(run)
    }

    private func content(elapsedSeconds: Int) -> some View {
        let minute = elapsedSeconds / 60
        let live = self.live ?? plan.schedule
        let placements = live.placements
        // In the hands: begun, not ticked off, and — with an unattended
        // part — still in its hands-on minutes.
        let narrator = narrator(minute: minute)
        let handsNow = narrator.handsNow
        let unattended = placements.filter { placement in
            placement.task.unattendedMinutes > 0 && placement.handsEnd <= minute && minute < placement.end
                && finished[placement.id] == nil
        }
        let upcoming = placements.filter { candidate in candidate.start > minute && !handsNow.contains { $0.id == candidate.id } }
            .sorted { ($0.start, $0.task.id) < ($1.start, $1.task.id) }
        let endedPots = placements.filter { placement in
            (placement.task.unattendedMinutes > 0 || placement.task.handsMinutes == 0)
                && placement.end <= minute && finished[placement.id] == nil
        }
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
                        Text(clockMode.explanation)
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
                    voiceRow
                    section("Jetzt", systemImage: "hand.raised.fill") {
                        if handsNow.isEmpty {
                            if let next = upcoming.first {
                                Text(clockMode.showsClock ? "Hände frei, in \(next.start - minute) Min. weiter" : "Hände frei, der Topf braucht noch")
                                    .font(Theme.bodyFont(24).weight(.semibold))
                                    .foregroundColor(Theme.subtitle)
                            } else if doneCount == placements.count {
                                Text("Fertig, anrichten!")
                                    .font(Theme.bodyFont(28).weight(.semibold))
                                    .foregroundColor(Theme.good)
                            }
                        }
                        ForEach(handsNow) { placement in
                            let overdue = clockMode.showsClock && minute >= placement.start + placement.task.handsMinutes
                            let pot = placement.task.unattendedMinutes > 0
                            let detail: LocalizedStringKey = !clockMode.showsClock
                                ? (pot ? "dann \(placement.task.unattendedMinutes) Min. von allein" : "")
                                : overdue ? "überfällig" : "noch \(placement.start + placement.task.handsMinutes - minute) Min."
                            stepLine(placement, ingredients: plan.dish.ingredients(for: placement.task),
                                     detail: detail,
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
                                         detail: clockMode.showsClock ? "in \(placement.start - minute) Min." : "")
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
        // Read aloud what is new: a step come into the hands, a pot that is
        // done. Once each; the first step at the start, too.
        .onChange(of: handsNow.map(\.id), initial: true) { _, ids in
            guard readAloud, startedAt != nil, let first = ids.first, !announcedSteps.contains(first),
                  let placement = handsNow.first(where: { $0.id == first }) else { return }
            announcedSteps.insert(first)
            speaker.speak(narrator.stepSentence(placement))
        }
        .onChange(of: endedPots.map(\.id)) { _, ids in
            guard readAloud, startedAt != nil else { return }
            let fresh = ids.filter { !announcedEnds.contains($0) }
            guard !fresh.isEmpty else { return }
            announcedEnds.formUnion(fresh)
            let names = fresh.compactMap { id in endedPots.first { $0.id == id }?.task.name }
            speaker.speak(names.map { String(format: spoken("%@: die Zeit ist um."), $0) }.joined(separator: " "))
        }
        .onChange(of: doneCount == placements.count && startedAt != nil) { _, done in
            if done, readAloud { speaker.speak(spoken("Fertig, anrichten!")) }
        }
    }

    // MARK: Voice

    /// Two switches under the clock: the app talks, the app listens.
    private var voiceRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    readAloud.toggle()
                    if !readAloud { speaker.stop() }
                } label: {
                    Label("Vorlesen", systemImage: readAloud ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(Theme.bodyFont(15).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(readAloud ? Theme.accentText : Theme.subtitle)
                .accessibilityLabel(readAloud ? "Vorlesen ausschalten" : "Vorlesen einschalten")
                Button {
                    toggleVoice()
                } label: {
                    Label("Sprachbefehle", systemImage: voice.isActive ? "mic.fill" : "mic")
                        .font(Theme.bodyFont(15).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(voice.isActive ? Theme.accentText : Theme.subtitle)
                .accessibilityLabel(voice.isActive ? "Sprachbefehle beenden" : "Sprachbefehle starten")
            }
            if voice.isActive {
                voiceStatus
            }
        }
    }

    @ViewBuilder
    private var voiceStatus: some View {
        switch voice.state {
        case .preparing:
            Label("Spracherkennung wird vorbereitet …", systemImage: "ellipsis")
                .font(Theme.bodyFont(13)).foregroundColor(Theme.subtitle)
        case .listening:
            let words = CookVoiceCommands.hintWords(languageCode: locale.identifier)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sage „\(words[0])“, „\(words[1])“, „\(words[2])“ oder „\(words[3])“.")
                    .font(Theme.bodyFont(13)).foregroundColor(Theme.subtitle)
                if let heard = voice.lastHeard {
                    Text("Gehört: \(commandWord(heard))")
                        .font(Theme.bodyFont(13)).foregroundColor(Theme.accentText)
                }
            }
        case .microphoneDenied:
            Label("Ohne Mikrofon kann der Kochmodus nicht zuhören. Erlaube den Zugriff in den Einstellungen.", systemImage: "mic.slash")
                .font(Theme.bodyFont(13)).foregroundColor(Theme.danger)
        case .unavailable:
            Label("Die Spracherkennung ist für diese Sprache auf diesem Gerät nicht verfügbar.", systemImage: "mic.slash")
                .font(Theme.bodyFont(13)).foregroundColor(Theme.danger)
        case .failed(let message):
            Label { Text(verbatim: message) } icon: { Image(systemName: "mic.slash") }
                .font(Theme.bodyFont(13)).foregroundColor(Theme.danger)
        case .off:
            EmptyView()
        }
    }

    /// The word on screen for a command that was heard.
    private func commandWord(_ command: CookVoiceCommand) -> String {
        let words = CookVoiceCommands.hintWords(languageCode: locale.identifier)
        switch command {
        case .done: return words[0]
        case .potOn: return words[1]
        case .read: return words[2]
        case .next: return words[3]
        case .undo: return spoken("Zurück")
        case .ingredients: return spoken("Zutaten")
        case .timing: return spoken("Wie lange")
        case .pause: return spoken("Pause")
        case .resume: return spoken("Weitermachen")
        case .stop: return spoken("Stopp")
        }
    }

    private func toggleVoice() {
        if voice.isActive {
            stopVoice()
        } else {
            speaker.managesAudioSession = false
            voice.onCommand = { command in handle(command) }
            Task {
                await voice.start(languageCode: locale.identifier)
                if voice.state == .listening {
                    let words = CookVoiceCommands.hintWords(languageCode: locale.identifier)
                    speaker.speak(String(format: spoken("Ich höre zu. Sage %@, %@, %@ oder %@."),
                                         words[0], words[1], words[2], words[3]))
                } else {
                    speaker.managesAudioSession = true
                }
            }
        }
    }

    private func stopVoice() {
        guard voice.isActive else { return }
        voice.stop()
        speaker.managesAudioSession = true
    }

    /// Carries out a spoken command on what is in the hands right now.
    private func handle(_ command: CookVoiceCommand) {
        let minute = elapsedSeconds(at: .now) / 60
        let current = narrator(minute: minute).handsNow
        switch command {
        case .done:
            guard let step = current.first else { speaker.speak(spoken("Gerade ist nichts in der Hand.")); return }
            if step.task.unattendedMinutes > 0 {
                putOn(step.id, minute: minute)
                speaker.speak(spoken("Steht.") + " " + narrator(minute: minute).followUp(after: step.id))
            } else {
                tickOff(step.id, minute: minute)
                speaker.speak(spoken("Erledigt.") + " " + narrator(minute: minute).followUp(after: step.id))
            }
        case .potOn:
            guard let pot = current.first(where: { $0.task.unattendedMinutes > 0 }) else {
                speaker.speak(spoken("Gerade steht kein Topf und kein Ofen an."))
                return
            }
            putOn(pot.id, minute: minute)
            speaker.speak(spoken("Steht.") + " " + narrator(minute: minute).followUp(after: pot.id))
        case .undo:
            guard !tickHistory.isEmpty else { speaker.speak(spoken("Es gibt nichts zurückzunehmen.")); return }
            undoLastTick()
            speaker.speak(spoken("Zurückgenommen."))
        case .read:
            speaker.speak(narrator(minute: minute).now())
        case .next:
            speaker.speak(narrator(minute: minute).followUp(after: current.first?.id, always: true))
        case .ingredients:
            guard let step = current.first else { speaker.speak(spoken("Gerade ist nichts in der Hand.")); return }
            let ingredients = plan.dish.ingredients(for: step.task)
            speaker.speak(ingredients.isEmpty ? spoken("Dieser Schritt hat keine Zutaten.")
                                              : KitchenSpokenText.lines(for: ingredients, locale: locale) + ".")
        case .timing:
            speaker.speak(narrator(minute: minute).timing())
        case .pause:
            pause()
            speaker.speak(spoken("Pause, die Uhr steht."))
        case .resume:
            if pausedAt != nil {
                resume()
                speaker.speak(spoken("Weiter geht's.") + " " + narrator(minute: minute).followUp(after: nil))
            } else {
                speaker.speak(spoken("Die Uhr läuft schon."))
            }
        case .stop:
            speaker.stop()
        }
    }

    /// A sentence the app says, in the app's language.
    private func spoken(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    /// The sentences for `minute`, from the live plan and the ticks.
    private func narrator(minute: Int) -> CookNarrator {
        CookNarrator(plan: plan, schedule: live ?? plan.schedule, finished: finished, handsDone: handsDone,
                     showsClock: clockMode.showsClock, locale: locale, minute: minute)
    }

    /// Ticks made elsewhere — by Siri while the phone was locked — arrive
    /// through the saved state when the cook mode comes back.
    private func adoptExternalChanges() {
        guard startedAt != nil, let saved = CookRunState.load(), saved.dishID == plan.dish.id,
              (saved.revision ?? 0) > revision else { return }
        revision = saved.revision ?? 0
        finished = saved.finished
        handsDone = saved.handsDone
        tickHistory = saved.ticks
        doneSeconds = saved.doneSeconds
        handsDoneSeconds = saved.handsDoneSeconds
        startSeconds = saved.startSeconds
        pausedAt = saved.pausedAt
        pausedSeconds = saved.pausedSeconds
        remindersSignature = ""
        replan(minute: elapsedSeconds(at: .now) / 60)
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
            if !clockMode.showsClock {
                // Relaxed: no numbers, just the mood.
                Label(startedAt == nil ? "Entspannt kochen, ohne Uhr" : "Entspannt – ohne Uhr", systemImage: "leaf")
                    .font(Theme.bodyFont(20).weight(.semibold))
                    .foregroundColor(Theme.good)
                    .padding(.vertical, 8)
            }
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
            if !clockMode.showsClock {
                EmptyView()
            } else if clockMode == .challenge {
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
            if clockMode != .training {
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
            if !clockMode.showsClock {
                EmptyView()
            } else if live.makespan > plan.schedule.makespan {
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
