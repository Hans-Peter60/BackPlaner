//
//  CookIntents.swift
//  CookPlanner
//
//  The Siri side of the cook mode: what is in the hands, mark it done,
//  how long, and start cooking a dish. Hands in the pan is the moment the
//  first three are for, so they run in the background and answer in a
//  sentence; only starting a dish opens the app.
//
//  They work on the run the cook mode keeps in CookRunState and word
//  things with CookNarrator, the same as the screen and the voice
//  commands. A tick made here raises the state's revision; the cook mode
//  adopts it when it comes back to the front.
//

import AppIntents
import BakePlannerCore
import Foundation

// MARK: - The run as the intents see it

@MainActor
enum CookRunAccess {

    struct Live {
        let plan: DishPlan
        let state: CookRunState
        let schedule: KitchenSchedule
        let minute: Int
        let second: Int
        let clockStart: Date

        var narrator: CookNarrator {
            let mode = CookClockMode(rawValue: UserDefaults.standard.string(forKey: CookSettings.clockModeKey) ?? "") ?? .challenge
            return CookNarrator(plan: plan, schedule: schedule, finished: state.finished, handsDone: state.handsDone,
                                showsClock: mode.showsClock, locale: .current, minute: minute)
        }
    }

    /// The run under way with its live plan, or nil when nothing is cooking.
    static func live(now: Date = Date()) throws -> Live? {
        guard let state = CookRunState.load(), state.isResumable else { return nil }
        guard let dish = DishLookup.dish(id: state.dishID) else { throw CookIntentError.dishGone }
        let defaults = UserDefaults.standard
        let budget = defaults.object(forKey: CookSettings.budgetKey) as? Int ?? CookSettings.defaultBudget
        let burners = defaults.object(forKey: CookSettings.burnersKey) as? Int ?? CookSettings.defaultBurners
        let ovens = defaults.object(forKey: CookSettings.ovensKey) as? Int ?? CookSettings.defaultOvens
        guard let plan = DishPlan(dish: dish.scaled(by: CookSettings.portionFactor(for: dish.id)),
                                  budget: budget, burners: burners, ovens: ovens) else { throw CookIntentError.dishGone }
        let end = state.pausedAt ?? now
        let second = max(0, Int(end.timeIntervalSince(state.startedAt) - state.pausedSeconds))
        let minute = second / 60
        let schedule = (try? KitchenScheduler.replan(plan.dish.tasks, kitchen: plan.schedule.kitchen, budget: plan.schedule.budget,
                                                     previous: plan.schedule,
                                                     progress: KitchenProgress(now: minute, finished: state.finished,
                                                                               handsDone: state.handsDone))) ?? plan.schedule
        return Live(plan: plan, state: state, schedule: schedule, minute: minute, second: second,
                    clockStart: state.startedAt.addingTimeInterval(state.pausedSeconds))
    }

    /// Ticks the step in the hands: a pot is put on, anything else is done.
    /// Saves the state with a higher revision and brings reminders and
    /// alarms in line with the plan as it stands afterwards.
    static func tickCurrent(_ live: Live) throws -> (step: KitchenPlacement, putOn: Bool, after: Live) {
        guard let step = live.narrator.handsNow.first else { throw CookIntentError.nothingInHand }
        var state = live.state
        let putOn = step.task.unattendedMinutes > 0
        let lastHandsFree = max(
            state.handsDoneSeconds.values.max() ?? 0,
            state.doneSeconds.filter { key, _ in
                live.plan.dish.tasks.first { $0.id == key }.map { $0.handsMinutes > 0 && $0.unattendedMinutes == 0 } ?? false
            }.values.max() ?? 0)
        let start = max(step.start * 60, lastHandsFree)
        if putOn {
            state.startSeconds[step.id] = min(live.second, start)
            state.handsDoneSeconds[step.id] = live.second
            state.handsDone[step.id] = live.minute
            state.ticks.append(.init(id: step.id, kind: .hands))
        } else {
            if state.startSeconds[step.id] == nil { state.startSeconds[step.id] = min(live.second, start) }
            state.doneSeconds[step.id] = live.second
            state.finished[step.id] = live.minute
            state.ticks.append(.init(id: step.id, kind: .done))
        }
        state.revision = (state.revision ?? 0) + 1
        state.save()
        guard let after = try self.live() else { throw CookIntentError.noRun }
        if state.pausedAt == nil {
            let finished = Set(state.finished.keys)
            CookAlarms.shared.sync(schedule: after.schedule, finished: finished, minute: after.minute,
                                   clockStart: after.clockStart, dishName: live.plan.dish.name)
            CookReminders.shared.sync(schedule: after.schedule, finished: finished, minute: after.minute,
                                      clockStart: after.clockStart, dishName: live.plan.dish.name,
                                      ringing: CookAlarms.shared.alarmTasks(in: after.schedule, finished: finished, minute: after.minute))
        }
        return (step, putOn, after)
    }
}

enum CookIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noRun
    case nothingInHand
    case dishGone

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noRun: return "Gerade kochst Du nichts in CookPlanner."
        case .nothingInHand: return "Gerade ist nichts in der Hand."
        case .dishGone: return "Das Gericht des laufenden Kochvorgangs gibt es nicht mehr."
        }
    }
}

// MARK: - What is in the hands

struct CurrentStepIntent: AppIntent {

    static let title: LocalizedStringResource = "Was steht an"
    static let description = IntentDescription("Sagt, welcher Schritt gerade in der Hand ist, und was als Nächstes kommt.")
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        guard let live = try CookRunAccess.live() else { throw CookIntentError.noRun }
        let text = live.narrator.now()
        return .result(value: text, dialog: "\(text)")
    }
}

// MARK: - Mark done

struct MarkStepDoneIntent: AppIntent {

    static let title: LocalizedStringResource = "Schritt erledigt"
    static let description = IntentDescription("Hakt den Schritt in der Hand ab; einen Topf oder den Ofen setzt es auf, seine Zeit läuft dann.")
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        guard let live = try CookRunAccess.live() else { throw CookIntentError.noRun }
        let result = try CookRunAccess.tickCurrent(live)
        let lead = result.putOn ? String(localized: "Steht.") : String(localized: "Erledigt.")
        let text = lead + " " + result.after.narrator.followUp(after: result.step.id, always: true)
        return .result(dialog: "\(text)")
    }
}

// MARK: - How long

struct TimeLeftIntent: AppIntent {

    static let title: LocalizedStringResource = "Wie lange noch"
    static let description = IntentDescription("Sagt, wie lange der Schritt in der Hand, die Töpfe und der ganze Plan noch brauchen.")
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        guard let live = try CookRunAccess.live() else { throw CookIntentError.noRun }
        let text = live.narrator.timing()
        return .result(value: text, dialog: "\(text)")
    }
}

// MARK: - Start cooking

struct StartCookingIntent: AppIntent {

    static let title: LocalizedStringResource = "Kochen starten"
    static let description = IntentDescription("Öffnet ein Gericht in CookPlanner und startet den Kochmodus.")
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Gericht")
    var dish: DishEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(DishDeepLink.url(dishID: dish.id, startsCooking: true)))
    }
}
