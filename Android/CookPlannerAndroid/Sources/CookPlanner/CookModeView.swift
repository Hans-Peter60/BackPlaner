import BakePlannerCore
import BakePlannerSpeech
import CookPlannerMedia
import SkipKit
import SwiftUI

/// The plan run against the clock, as on the iPhone (CookModeView.swift
/// there): what the hands do now, what comes next, what runs on its own.
/// Each hands-on step is ticked off; a pot or oven step is ticked twice,
/// "Steht" when the hands are done, and off when it is taken off (or the
/// clock ends it). Done early or late, the rest is replanned from that
/// minute (KitchenScheduler.replan). Every change goes to cook-run.json.
struct CookModeView: View {
    let plan: DishPlan
    @State var startedAt: Date?
    @State var pausedAt: Date?
    @State var pausedSeconds: Double = 0
    @State var finished: [String: Int] = [:]
    @State var handsDone: [String: Int] = [:]
    @State var ticks: [CookRunState.Tick] = []
    @State var doneSeconds: [String: Int] = [:]
    @State var handsDoneSeconds: [String: Int] = [:]
    @State var startSeconds: [String: Int] = [:]
    @State var live: KitchenSchedule?
    @State var now = Date()
    @State var clockMode = CookClockMode.stored
    @State var confirmsEnd = false
    @State var runSaved = false
    /// Notifications are not allowed: the cook should know before the
    /// phone goes dark.
    @State var silenced = false
    /// Reads each step that comes into the hands, and each pot that is
    /// done, aloud (the iPhone's switch, same key).
    @State var readAloud = SettingsFile.flag("settings.readAloud", default: false)
    @State var speaker = StepSpeaker()
    @State var announcedSteps: Set<String> = []
    @State var announcedEnds: Set<String> = []
    @State var announcedDone = false
    /// Listens for "Erledigt", "Steht", "Was kommt" and the rest.
    @State var voice = VoiceListener()
    @State var listening = false
    @State var heardSeen = 0
    @State var voiceNote = ""
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase

    init(plan: DishPlan, restoring state: CookRunState? = nil) {
        self.plan = plan
        if let state {
            _startedAt = State(initialValue: state.startedAt)
            _pausedAt = State(initialValue: state.pausedAt)
            _pausedSeconds = State(initialValue: state.pausedSeconds)
            _finished = State(initialValue: state.finished)
            _handsDone = State(initialValue: state.handsDone)
            _ticks = State(initialValue: state.ticks)
            _doneSeconds = State(initialValue: state.doneSeconds)
            _handsDoneSeconds = State(initialValue: state.handsDoneSeconds)
            _startSeconds = State(initialValue: state.startSeconds)
            if let mode = state.clockMode.flatMap(CookClockMode.init(rawValue:)) {
                _clockMode = State(initialValue: mode)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground().ignoresSafeArea()
                ScrollView {
                    content
                        .padding(16)
                }
            }
            .navigationTitle(String(localized: "Kochen", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Beenden", bundle: .module)) {
                        if startedAt == nil {
                            end(keepingRecord: false)
                        } else {
                            confirmsEnd = true
                        }
                    }
                }
            }
            .alert(String(localized: "Kochen beenden?", bundle: .module), isPresented: $confirmsEnd) {
                if hasRecord {
                    Button(String(localized: "Beenden und Protokoll sichern", bundle: .module)) { end(keepingRecord: true) }
                    Button(String(localized: "Beenden ohne Protokoll", bundle: .module), role: .destructive) { end(keepingRecord: false) }
                } else {
                    Button(String(localized: "Beenden", bundle: .module), role: .destructive) { end(keepingRecord: false) }
                }
                Button(String(localized: "Weiterkochen", bundle: .module), role: .cancel) {}
            } message: {
                Text(hasRecord
                     ? String(localized: "Das Protokoll hält fest, wann jeder Schritt erledigt war.", bundle: .module)
                     : String(localized: "Noch ist kein Schritt erledigt; es gibt nichts festzuhalten.", bundle: .module))
            }
        }
        // Only "Beenden" ends a run: Android's back gesture closed the sheet
        // and left the run going unseen, its banners still coming (as on the
        // iPhone, where the cook mode cannot be swiped away).
        .interactiveDismissDisabled()
        // A sheet opened from the root (a resumed run) sits outside the
        // root's tint.
        .tint(Palette.accent(colorScheme))
        // The phone lies on the counter while the hands are busy.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            speaker.shutdown()
            voice.stop()
        }
        .task {
            // The clock: a second at a time; the plan moves on each minute.
            var lastMinute = -1
            while !Task.isCancelled {
                now = Date()
                let minute = elapsedSeconds / 60
                if minute != lastMinute {
                    lastMinute = minute
                    replan(minute: minute)
                }
                announce(minute: minute)
                listen(minute: minute)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Clock

    /// Seconds on the cooking clock: since the start, less the pauses.
    var elapsedSeconds: Int {
        guard let startedAt else { return 0 }
        let end = pausedAt ?? now
        return max(0, Int(end.timeIntervalSince(startedAt) - pausedSeconds))
    }

    var schedule: KitchenSchedule { live ?? plan.schedule }

    // MARK: Screen

    @ViewBuilder
    private var content: some View {
        let minute = elapsedSeconds / 60
        let placements = schedule.placements
        let handsNow = self.handsNow(minute: minute)
        let upcoming = placements.filter { candidate in candidate.start > minute && !handsNow.contains { $0.id == candidate.id } }
            .sorted { ($0.start, $0.task.id) < ($1.start, $1.task.id) }
        let unattended = placements.filter { placement in
            placement.task.unattendedMinutes > 0 && placement.handsEnd <= minute && minute < placement.end
                && finished[placement.id] == nil
        }
        let doneCount = placements.filter { placement in
            finished[placement.id] != nil
                || ((placement.task.unattendedMinutes > 0 || placement.task.handsMinutes == 0) && placement.end <= minute)
        }.count

        VStack(alignment: .leading, spacing: 16) {
            clockCard(minute: minute)

            if startedAt == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Picker(String(localized: "Uhr", bundle: .module), selection: $clockMode) {
                        ForEach(CookClockMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(clockMode.explanation)
                        .font(.footnote)
                        .foregroundStyle(Palette.subtitle(colorScheme))
                }
                Button {
                    SettingsFile.set(clockMode.rawValue, forKey: CookClockMode.settingsKey)
                    startedAt = Date()
                    now = Date()
                    persist()
                    CookReminders.cancel(schedule: schedule)
                    Task {
                        silenced = !(await CookReminders.requestAuthorization())
                        syncReminders(minute: elapsedSeconds / 60)
                    }
                } label: {
                    Label(String(localized: "Start", bundle: .module), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Toggle(String(localized: "Vorlesen", bundle: .module), isOn: $readAloud)
                    .onChange(of: readAloud) { _, on in
                        SettingsFile.set(on, forKey: "settings.readAloud")
                        if on {
                            // What is in the hands now is read at once.
                            announcedSteps = []
                            announce(minute: elapsedSeconds / 60)
                        } else {
                            speaker.stop()
                        }
                    }
                Toggle(String(localized: "Sprachbefehle", bundle: .module), isOn: Binding(get: { listening }, set: { on in
                    if on { startListening() } else { stopListening() }
                }))
                if listening {
                    Text(voiceNote.isEmpty
                         ? String(localized: "Sag „Erledigt“, „Steht“, „Was kommt“, „Zutaten“ oder „Wie lange“.", bundle: .module)
                         : voiceNote)
                        .font(.footnote)
                        .foregroundStyle(Palette.subtitle(colorScheme))
                }
                HStack(spacing: 10) {
                    Button(String(localized: "Rückgängig", bundle: .module)) { undoLastTick() }
                        .buttonStyle(.bordered)
                        .disabled(ticks.isEmpty)
                    Spacer()
                    if pausedAt == nil {
                        Button(String(localized: "Pause", bundle: .module)) { pause() }
                            .buttonStyle(.bordered)
                    } else {
                        Button(String(localized: "Weiter", bundle: .module)) { resume() }
                            .buttonStyle(.borderedProminent)
                    }
                }

                section(String(localized: "Jetzt", bundle: .module)) {
                    if handsNow.isEmpty {
                        if let next = upcoming.first {
                            Text(clockMode.showsClock
                                 ? String(localized: "Hände frei, in \(next.start - minute) Min. weiter", bundle: .module)
                                 : String(localized: "Hände frei, der Topf braucht noch", bundle: .module))
                                .font(.title3)
                                .foregroundStyle(Palette.subtitle(colorScheme))
                        } else if doneCount == placements.count {
                            Text(String(localized: "Fertig, anrichten!", bundle: .module))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(Palette.good(colorScheme))
                        }
                    }
                    ForEach(handsNow, id: \.id) { placement in
                        CurrentStepView(placement: placement,
                                        ingredients: plan.dish.ingredients(for: placement.task),
                                        detail: handsDetail(placement, minute: minute),
                                        overdue: clockMode.showsClock && minute >= placement.start + placement.task.handsMinutes,
                                        onDone: {
                                            if placement.task.unattendedMinutes > 0 {
                                                putOn(placement.id, minute: minute)
                                            } else {
                                                tickOff(placement.id, minute: minute)
                                            }
                                        })
                    }
                }

                if !upcoming.isEmpty {
                    section(String(localized: "Gleich", bundle: .module)) {
                        ForEach(Array(upcoming.prefix(3)), id: \.id) { placement in
                            StepLine(placement: placement,
                                     ingredients: plan.dish.ingredients(for: placement.task),
                                     detail: clockMode.showsClock ? String(localized: "in \(placement.start - minute) Min.", bundle: .module) : "",
                                     onDone: nil)
                        }
                    }
                }
                if !unattended.isEmpty {
                    section(String(localized: "Läuft von allein", bundle: .module)) {
                        ForEach(unattended, id: \.id) { placement in
                            StepLine(placement: placement, ingredients: [],
                                     detail: unattendedDetail(placement, minute: minute),
                                     onDone: { tickOff(placement.id, minute: minute) })
                        }
                    }
                }
                if doneCount > 0 {
                    section(String(localized: "Erledigt", bundle: .module)) {
                        Text(String(localized: "\(doneCount) von \(placements.count) Schritten", bundle: .module))
                            .font(.subheadline)
                            .foregroundStyle(Palette.subtitle(colorScheme))
                    }
                }
            }
        }
    }

    /// In the hands: begun, not ticked off, and — with an unattended part —
    /// still in its hands-on minutes. Relaxed: once the hands are free, the
    /// next step whose predecessors are through comes forward.
    private func handsNow(minute: Int) -> [KitchenPlacement] {
        let placements = schedule.placements
        let inHands = placements.filter { placement in
            placement.task.handsMinutes > 0 && placement.start <= minute && finished[placement.id] == nil
                && handsDone[placement.id] == nil
                && (placement.task.unattendedMinutes == 0 || minute < placement.handsEnd)
        }
        if !inHands.isEmpty || clockMode.showsClock { return inHands }
        let upcoming = placements.filter { $0.start > minute }.sorted { ($0.start, $0.task.id) < ($1.start, $1.task.id) }
        guard let next = upcoming.first(where: { candidate in
            candidate.task.handsMinutes > 0 && candidate.task.after.allSatisfy { id in
                finished[id] != nil || placements.contains { $0.id == id && $0.task.handsMinutes == 0 && $0.end <= minute }
                    || placements.contains { $0.id == id && $0.task.unattendedMinutes > 0 && $0.end <= minute }
            }
        }) else { return [] }
        return [next]
    }

    private func handsDetail(_ placement: KitchenPlacement, minute: Int) -> String {
        let pot = placement.task.unattendedMinutes > 0
        if !clockMode.showsClock {
            return pot ? String(localized: "dann \(placement.task.unattendedMinutes) Min. von allein", bundle: .module) : ""
        }
        if minute >= placement.start + placement.task.handsMinutes {
            return String(localized: "überfällig", bundle: .module)
        }
        return String(localized: "noch \(placement.start + placement.task.handsMinutes - minute) Min.", bundle: .module)
    }

    private func unattendedDetail(_ placement: KitchenPlacement, minute: Int) -> String {
        guard let window = placement.task.unattendedWindow else {
            return String(localized: "noch \(placement.end - minute) Min.", bundle: .module)
        }
        let earliest = placement.start + placement.task.handsMinutes + window.lowerBound
        let latest = placement.start + placement.task.handsMinutes + window.upperBound
        if minute < earliest {
            return String(localized: "noch \(earliest - minute)–\(latest - minute) Min.", bundle: .module)
        }
        return String(localized: "bis zu \(max(0, latest - minute)) Min.", bundle: .module)
    }

    private func clockCard(minute: Int) -> some View {
        let elapsed = elapsedSeconds
        let remaining = max(0, schedule.makespan * 60 - elapsed)
        return VStack(spacing: 4) {
            Text(plan.dish.name)
                .font(.subheadline)
                .foregroundStyle(Palette.subtitle(colorScheme))
                .multilineTextAlignment(.center)
            if !clockMode.showsClock {
                Text(startedAt == nil ? String(localized: "Entspannt kochen, ohne Uhr", bundle: .module)
                                      : String(localized: "Entspannt – ohne Uhr", bundle: .module))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.good(colorScheme))
                    .padding(.vertical, 8)
            }
            if silenced {
                Text(String(localized: "Mitteilungen sind aus – bei dunklem Bildschirm meldet sich CookPlanner nicht. Einschalten in den Android-Einstellungen unter Apps → CookPlanner.", bundle: .module))
                    .font(.footnote)
                    .foregroundStyle(Palette.danger(colorScheme))
            }
            if pausedAt != nil {
                Text(String(localized: "Pause, die Uhr steht", bundle: .module))
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.danger(colorScheme))
            }
            if clockMode == .challenge {
                let target = (plan.schedule.budget ?? schedule.makespan) * 60
                let left = target - elapsed
                Text(left >= 0 ? KitchenCookRun.clockText(left) : "−" + KitchenCookRun.clockText(-left))
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(left < 0 ? Palette.danger(colorScheme) : Palette.title(colorScheme))
                if left >= 0 {
                    Text(String(localized: "Budget \(target / 60) Min. · Plan fertig in Minute \(schedule.makespan)", bundle: .module))
                        .font(.footnote)
                        .foregroundStyle(Palette.subtitle(colorScheme))
                } else {
                    Text(String(localized: "Zeit um – \(KitchenCookRun.clockText(-left) /*%@*/) drüber", bundle: .module))
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.danger(colorScheme))
                }
            } else if clockMode == .training {
                Text(KitchenCookRun.clockText(elapsed))
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Palette.title(colorScheme))
                if remaining > 0 {
                    Text(String(localized: "Plan \(schedule.makespan) Min. · noch \(KitchenCookRun.clockText(remaining) /*%@*/)", bundle: .module))
                        .font(.footnote)
                        .foregroundStyle(Palette.subtitle(colorScheme))
                }
            }
            if clockMode.showsClock, startedAt != nil {
                if schedule.makespan > plan.schedule.makespan {
                    Text(String(localized: "Fertig in Minute \(schedule.makespan), \(schedule.makespan - plan.schedule.makespan) Min. später als geplant", bundle: .module))
                        .font(.footnote)
                        .foregroundStyle(Palette.danger(colorScheme))
                } else if schedule.makespan < plan.schedule.makespan {
                    Text(String(localized: "Fertig in Minute \(schedule.makespan), \(plan.schedule.makespan - schedule.makespan) Min. früher als geplant", bundle: .module))
                        .font(.footnote)
                        .foregroundStyle(Palette.good(colorScheme))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.title(colorScheme))
            content()
        }
        .cardStyle()
    }

    // MARK: Voice

    /// Reads what is new aloud, once each: a step come into the hands, a
    /// pot that has run its time, the end.
    private func announce(minute: Int) {
        guard readAloud, startedAt != nil, pausedAt == nil else { return }
        let narrator = CookNarrator(dish: plan.dish, showsClock: clockMode.showsClock, minute: minute)
        let language = AppSettings.locale.identifier
        if let step = handsNow(minute: minute).first, !announcedSteps.contains(step.id) {
            announcedSteps.insert(step.id)
            speaker.speak(narrator.stepSentence(step), languageCode: language)
            return
        }
        let ended = schedule.placements.filter { placement in
            placement.task.unattendedMinutes > 0 && placement.end <= minute && finished[placement.id] == nil
                && !announcedEnds.contains(placement.id)
        }
        if !ended.isEmpty {
            for placement in ended { announcedEnds.insert(placement.id) }
            speaker.speak(ended.map { narrator.potDone($0.task.name) }.joined(separator: " "), languageCode: language)
            return
        }
        let doneCount = schedule.placements.filter { placement in
            finished[placement.id] != nil
                || ((placement.task.unattendedMinutes > 0 || placement.task.handsMinutes == 0) && placement.end <= minute)
        }.count
        if doneCount == schedule.placements.count, !announcedDone {
            announcedDone = true
            speaker.speak(narrator.allDone, languageCode: language)
        }
    }

    private func startListening() {
        Task {
            let status = await PermissionManager.requestPermission(.RECORD_AUDIO)
            guard status == .authorized else {
                voiceNote = String(localized: "Ohne Mikrofon kann der Kochmodus nicht zuhören. Erlaube den Zugriff in den Einstellungen.", bundle: .module)
                listening = false
                return
            }
            heardSeen = voice.heardCount
            voiceNote = ""
            listening = true
            voice.start(languageTag: AppSettings.locale.identifier.replacingOccurrences(of: "_", with: "-"))
        }
    }

    private func stopListening() {
        listening = false
        voice.stop()
    }

    /// What the listener heard since the last look, as a command; and the
    /// microphone muted while the app talks, so its voice is no command.
    private func listen(minute: Int) {
        guard listening else { return }
        voice.isMuted = speaker.isSpeaking
        if voice.state == "unavailable" {
            voiceNote = String(localized: "Auf diesem Gerät gibt es keine Spracherkennung.", bundle: .module)
            return
        }
        guard voice.heardCount != heardSeen else { return }
        heardSeen = voice.heardCount
        let language = AppSettings.locale.language.languageCode?.identifier ?? "de"
        guard let command = CookVoiceCommands.command(in: voice.lastHeard, languageCode: language) else { return }
        handle(command, minute: minute)
    }

    private func handle(_ command: CookVoiceCommand, minute: Int) {
        let narrator = CookNarrator(dish: plan.dish, showsClock: clockMode.showsClock, minute: minute)
        let language = AppSettings.locale.identifier
        let inHands = handsNow(minute: minute)
        switch command {
        case .done, .potOn:
            guard let step = inHands.first else {
                speaker.speak(narrator.followUp(handsNow: inHands, schedule: schedule, finished: finished), languageCode: language)
                return
            }
            if step.task.unattendedMinutes > 0 {
                putOn(step.id, minute: minute)
            } else {
                tickOff(step.id, minute: minute)
            }
            // The next step is read by announce(), once.
        case .undo:
            undoLastTick()
        case .read:
            if let step = inHands.first {
                speaker.speak(narrator.stepSentence(step), languageCode: language)
            } else {
                speaker.speak(narrator.followUp(handsNow: inHands, schedule: schedule, finished: finished), languageCode: language)
            }
        case .next:
            let upcoming = schedule.placements.filter { $0.start > minute && $0.task.handsMinutes > 0 }
            let after = inHands.isEmpty ? [] : Array(upcoming.prefix(1))
            speaker.speak(narrator.followUp(handsNow: after, schedule: schedule, finished: finished), languageCode: language)
        case .ingredients:
            if let step = inHands.first, !plan.dish.ingredients(for: step.task).isEmpty {
                speaker.speak(KitchenSpokenText.lines(for: plan.dish.ingredients(for: step.task), locale: AppSettings.locale),
                              languageCode: language)
            } else {
                speaker.speak(String(localized: "Für diesen Schritt keine Zutaten.", bundle: .module), languageCode: language)
            }
        case .timing:
            speaker.speak(narrator.timing(handsNow: inHands, schedule: schedule, finished: finished), languageCode: language)
        case .pause:
            pause()
        case .resume:
            resume()
        case .stop:
            speaker.stop()
        }
    }

    // MARK: Actions

    private func persist() {
        guard let startedAt else { return }
        CookRunState(dishID: plan.dish.id, startedAt: startedAt, pausedAt: pausedAt, pausedSeconds: pausedSeconds,
                     finished: finished, handsDone: handsDone, ticks: ticks, doneSeconds: doneSeconds,
                     handsDoneSeconds: handsDoneSeconds, startSeconds: startSeconds,
                     clockMode: clockMode.rawValue).save()
    }

    private func replan(minute: Int) {
        guard startedAt != nil else { return }
        let previous = live ?? plan.schedule
        live = (try? KitchenScheduler.replan(plan.dish.tasks, kitchen: plan.schedule.kitchen, budget: plan.schedule.budget,
                                             previous: previous,
                                             progress: KitchenProgress(now: minute, finished: finished, handsDone: handsDone))) ?? previous
        syncReminders(minute: minute)
    }

    /// The banners for the live plan as it stands, while the clock runs.
    /// Not in the background: Android keeps the app running there, and a
    /// step left unticked would push the next one's banner along every
    /// minute, so it never came. As on the iPhone, where the app sleeps,
    /// the banners stay at the times they had when the phone went dark.
    private func syncReminders(minute: Int) {
        guard let startedAt, pausedAt == nil, scenePhase == .active else { return }
        CookReminders.sync(schedule: schedule, finished: finished, handsDone: handsDone, minute: minute,
                           clockStart: startedAt.addingTimeInterval(pausedSeconds))
    }

    private func pause() {
        guard startedAt != nil, pausedAt == nil else { return }
        pausedAt = Date()
        CookReminders.cancel(schedule: schedule)
        persist()
    }

    private func resume() {
        guard let pausedAt else { return }
        pausedSeconds += Date().timeIntervalSince(pausedAt)
        self.pausedAt = nil
        now = Date()
        syncReminders(minute: elapsedSeconds / 60)
        persist()
    }

    /// The second the hands were last free: the latest tick of a
    /// hands-only step, or the latest "Steht".
    private var lastHandsFreeSecond: Int {
        let handsOnly = doneSeconds.filter { key, _ in
            plan.dish.tasks.first { $0.id == key }.map { $0.handsMinutes > 0 && $0.unattendedMinutes == 0 } ?? false
        }.values.max() ?? 0
        return max(handsOnly, handsDoneSeconds.values.max() ?? 0)
    }

    private func tickOff(_ id: String, minute: Int) {
        let second = elapsedSeconds
        let placement = schedule.placement(of: id)
        if startSeconds[id] == nil {
            var start = (placement?.start ?? 0) * 60
            if (placement?.task.handsMinutes ?? 0) > 0 { start = max(start, lastHandsFreeSecond) }
            startSeconds[id] = min(second, start)
        }
        doneSeconds[id] = second
        finished[id] = minute
        ticks.append(CookRunState.Tick(id: id, kind: .done))
        replan(minute: minute)
        persist()
    }

    /// The hands are done with a pot or oven step: it runs on its own now.
    private func putOn(_ id: String, minute: Int) {
        let second = elapsedSeconds
        let placement = schedule.placement(of: id)
        let start = max((placement?.start ?? 0) * 60, lastHandsFreeSecond)
        startSeconds[id] = min(second, start)
        handsDoneSeconds[id] = second
        handsDone[id] = minute
        ticks.append(CookRunState.Tick(id: id, kind: .hands))
        replan(minute: minute)
        persist()
    }

    private func undoLastTick() {
        guard let tick = ticks.popLast() else { return }
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
        replan(minute: elapsedSeconds / 60)
        persist()
    }

    private var hasRecord: Bool {
        guard startedAt != nil else { return false }
        if !doneSeconds.isEmpty || !handsDoneSeconds.isEmpty { return true }
        let minute = elapsedSeconds / 60
        return schedule.placements.contains {
            ($0.task.unattendedMinutes > 0 || $0.task.handsMinutes == 0) && $0.end <= minute
        }
    }

    private func end(keepingRecord: Bool) {
        if keepingRecord { saveRun() }
        CookReminders.cancel(schedule: schedule)
        CookRunState.clear()
        dismiss()
    }

    /// The stopwatch record: every ticked step with its seconds, and the
    /// pots and waits that ran their time without a tick.
    private func saveRun() {
        guard !runSaved, let startedAt else { return }
        runSaved = true
        let total = elapsedSeconds
        let minute = total / 60
        var steps = [KitchenCookRun.Step]()
        for placement in schedule.placements {
            let task = placement.task
            let planned = plan.schedule.placement(of: task.id)?.start ?? placement.start
            if let done = doneSeconds[task.id] {
                steps.append(KitchenCookRun.Step(taskID: task.id, name: task.name, component: task.component,
                                                 plannedMinutes: task.minutes, plannedStart: planned,
                                                 startedSecond: startSeconds[task.id] ?? placement.start * 60,
                                                 doneSecond: done, tickedByCook: true))
            } else if task.unattendedMinutes > 0 || task.handsMinutes == 0, placement.end <= minute {
                steps.append(KitchenCookRun.Step(taskID: task.id, name: task.name, component: task.component,
                                                 plannedMinutes: task.minutes, plannedStart: planned,
                                                 startedSecond: startSeconds[task.id] ?? placement.start * 60,
                                                 doneSecond: placement.end * 60, tickedByCook: false))
            }
        }
        guard !steps.isEmpty else { return }
        var run = KitchenCookRun(dishID: plan.dish.id, dishName: plan.dish.name, startedAt: startedAt,
                                 totalSeconds: total, plannedMinutes: plan.schedule.makespan,
                                 steps: steps, totalSteps: schedule.placements.count)
        if clockMode == .relaxed { run.relaxed = true }
        CookRunLog.shared.add(run)
    }
}

/// What is in the hands right now, read from across the kitchen: the name
/// large, the ingredients, the time left, and a big button to tick it off.
struct CurrentStepView: View {
    let placement: KitchenPlacement
    let ingredients: [KitchenIngredient]
    let detail: String
    let overdue: Bool
    let onDone: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(placement.task.name)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Palette.title(colorScheme))
            if !ingredients.isEmpty {
                Text(ingredients.map { $0.line(locale: AppSettings.locale) }.joined(separator: " · "))
                    .font(.title3)
                    .foregroundStyle(Palette.title(colorScheme))
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(overdue ? Palette.danger(colorScheme) : Palette.accentText(colorScheme))
                    }
                    Text(placement.task.component)
                        .font(.subheadline)
                        .foregroundStyle(Palette.subtitle(colorScheme))
                }
                Spacer()
                Button(action: onDone) {
                    Text(placement.task.unattendedMinutes > 0 ? String(localized: "Steht", bundle: .module)
                                                              : String(localized: "Erledigt", bundle: .module))
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A coming or running step: name, ingredients, component, minutes, and
/// for a running pot a button to take it off.
struct StepLine: View {
    let placement: KitchenPlacement
    let ingredients: [KitchenIngredient]
    let detail: String
    let onDone: (() -> Void)?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(placement.task.name)
                    .foregroundStyle(Palette.title(colorScheme))
                if !ingredients.isEmpty {
                    Text(ingredients.map { $0.line(locale: AppSettings.locale) }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Palette.title(colorScheme))
                }
                Text(placement.task.component)
                    .font(.caption)
                    .foregroundStyle(Palette.subtitle(colorScheme))
            }
            Spacer()
            if !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.accentText(colorScheme))
            }
            if let onDone {
                Button(action: onDone) {
                    Image(systemName: "checkmark.circle")
                }
                .accessibilityLabel(Text(String(localized: "Schritt erledigt", bundle: .module)))
            }
        }
    }
}
