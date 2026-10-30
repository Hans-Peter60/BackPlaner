//
//  PlannedStepIntents.swift
//  BackPlaner
//
//  The Siri side of the plan: what comes next, mark it done, push it back,
//  and when the dough goes into the oven. Hands in the dough is the moment
//  these are for, so every one of them runs in the background and answers
//  in a sentence; nothing here opens the app.
//
//  They work on the live Core Data steps, not the widget's plan snapshot,
//  and apply the same "which step matters now" rule as the main menu card
//  and the snapshot: a step that became due within the last hour and was
//  not marked done comes first, otherwise the earliest step still ahead.
//

import BakePlannerCore
import AppIntents
import CoreData
import Foundation

// MARK: - Store

/// Reads and changes planned steps for the intents. On the main actor: the
/// fetches go through the view context, which is a main-queue context, and
/// the shift and cancel paths of NotificationActions expect to be called
/// from there.
@MainActor
enum PlannedStepStore {

    /// The view context. Nonisolated so it can serve as the default of the
    /// `context` parameters below, which are evaluated outside the actor.
    nonisolated static var context: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    /// Every planned step the user should see at `now`, earliest first.
    /// Automatically-queued recurring steps far ahead stay out, as in
    /// every view of the plan.
    static func visibleSteps(at now: Date = Date(), in context: NSManagedObjectContext = context) throws -> [NextStep] {
        let request = NextStep.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return try context.fetch(request).filter { $0.isVisible(at: now) }
    }

    /// The step that matters at `now`, and whether its time has come. The
    /// same rule as `PlanSnapshot.currentStep(at:)` and the main menu card.
    static func currentStep(at now: Date = Date(), in context: NSManagedObjectContext = context) throws -> (step: NextStep, isDue: Bool)? {
        try CurrentStepRule.currentStep(in: visibleSteps(at: now, in: context), at: now, date: \.date)
    }

    /// The next step that puts dough into the oven: still ahead, or due
    /// within the last hour and not marked done.
    static func nextBakingStep(at now: Date = Date(), in context: NSManagedObjectContext = context) throws -> NextStep? {
        let horizon = now.addingTimeInterval(-PlanSnapshot.dueGracePeriod)
        return try visibleSteps(at: now, in: context).first {
            $0.date > horizon && BakePlanValidator.isBakingStartInstruction($0.instruction)
        }
    }

    /// The later steps of the same plan, the way shifting a step "with its
    /// followers" selects them.
    static func followingSteps(of step: NextStep, in context: NSManagedObjectContext = context) throws -> [NextStep] {
        let request = NextStep.fetchRequest()
        request.predicate = NotificationActions.followingStepsPredicate(
            recipeName: step.recipeName, after: step.date, step: step.step, planID: step.planID
        )
        return try context.fetch(request)
    }

    /// Removes the step together with its reminder — done and deleted are
    /// the same removal, as in the plan views.
    static func markDone(_ step: NextStep, in context: NSManagedObjectContext = context) throws {
        NotificationActions.cancelPendingNotification(for: step)
        context.delete(step)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Where a step lands when moved `minutes` in `direction` at `now`.
    ///
    /// Later: counted from now for a step that is already due — the way the
    /// reminder's postpone button does it — and from the step's own time
    /// for one still ahead. Earlier: only for a step still ahead, and never
    /// beyond now; asked to bring a step forward by more than it is away,
    /// it becomes due now. `nil` for a due step asked to come earlier.
    nonisolated static func shiftedDate(of stepDate: Date, isDue: Bool, minutes: Int,
                                        direction: StepShiftDirection, now: Date) -> Date? {
        let distance = TimeInterval(minutes * 60)
        switch direction {
        case .later:
            return (isDue ? now : stepDate).addingTimeInterval(distance)
        case .earlier:
            guard !isDue else { return nil }
            return max(stepDate.addingTimeInterval(-distance), now.addingTimeInterval(60))
        }
    }

    /// Moves the step (and, if asked, its followers) by `minutes`, which
    /// may be negative, reminders included. Wraps the completion-handler
    /// API the plan views use.
    static func shift(_ step: NextStep, byMinutes minutes: Int, includeFollowing: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NotificationActions.shiftScheduledStep(step, byMinutes: minutes, includeFollowing: includeFollowing) { result in
                continuation.resume(with: result)
            }
        }
    }
}

// MARK: - Errors

enum PlannedStepIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noPlannedSteps
    case noBakingStep
    case shiftedIntoPast
    case dueStepCannotComeEarlier
    case couldNotSave

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noPlannedSteps:  return "Es sind gerade keine Schritte geplant."
        case .noBakingStep:    return "In den geplanten Schritten steht kein Backschritt mehr an."
        case .shiftedIntoPast: return "Der verschobene Zeitpunkt muss in der Zukunft liegen."
        case .dueStepCannotComeEarlier: return "Der Schritt ist schon fällig und lässt sich nicht mehr vorziehen."
        case .couldNotSave:    return "Die Änderung konnte nicht gespeichert werden."
        }
    }
}

/// Which way a step moves. The titles read in the Shortcuts sentence
/// ("Nächsten Schritt um 15 Minuten nach vorne verschieben") and, with the
/// synonyms, at the end of the Siri phrase ("Nächsten Schritt in
/// BakePlanner vorziehen"). The raw values are stored in saved shortcuts
/// and must not change.
enum StepShiftDirection: String, AppEnum {
    case later
    case earlier

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Richtung")

    static let caseDisplayRepresentations: [StepShiftDirection: DisplayRepresentation] = [
        .later: DisplayRepresentation(title: "nach hinten verschieben",
                                      synonyms: ["verschieben", "nach hinten"]),
        .earlier: DisplayRepresentation(title: "nach vorne verschieben",
                                        synonyms: ["vorziehen", "nach vorne"])
    ]
}

// MARK: - Next step

struct NextStepIntent: AppIntent {

    static let title: LocalizedStringResource = "Nächster Backschritt"
    static let description = IntentDescription("Sagt, welcher geplante Schritt als Nächstes ansteht und wann.")
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        let now = Date()
        guard let current = try PlannedStepStore.currentStep(at: now) else {
            throw PlannedStepIntentError.noPlannedSteps
        }

        let instruction = IntentPhrasing.spokenInstruction(current.step.instruction)
        let recipeName = current.step.recipeName
        let when = IntentPhrasing.dateText(current.step.date, now: now)

        let dialog: IntentDialog = current.isDue
            ? "Jetzt fällig für \(recipeName): \(instruction)."
            : "Als Nächstes für \(recipeName): \(instruction), \(when)."
        return .result(value: instruction, dialog: dialog)
    }
}

// MARK: - Mark done

struct MarkStepDoneIntent: AppIntent {

    static let title: LocalizedStringResource = "Schritt erledigt"
    static let description = IntentDescription("Markiert den fälligen Schritt als erledigt und entfernt ihn aus dem Plan.")
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let now = Date()
        guard let current = try PlannedStepStore.currentStep(at: now) else {
            throw PlannedStepIntentError.noPlannedSteps
        }

        let instruction = IntentPhrasing.spokenInstruction(current.step.instruction)
        let recipeName = current.step.recipeName

        // A step that is not due yet is the next one, not the one at hand:
        // make sure before it disappears from the plan. A cancel throws and
        // ends the intent here, with nothing changed.
        if !current.isDue {
            let when = IntentPhrasing.dateText(current.step.date, now: now)
            try await requestConfirmation(
                dialog: "„\(instruction)“ für \(recipeName) ist erst \(when) fällig. Trotzdem als erledigt markieren?"
            )
        }

        do {
            try PlannedStepStore.markDone(current.step)
        } catch {
            throw PlannedStepIntentError.couldNotSave
        }

        if let next = try PlannedStepStore.currentStep(at: now) {
            let nextInstruction = IntentPhrasing.spokenInstruction(next.step.instruction)
            let nextWhen = IntentPhrasing.dateText(next.step.date, now: now)
            return .result(dialog: "Erledigt. Als Nächstes für \(next.step.recipeName): \(nextInstruction), \(nextWhen).")
        }
        return .result(dialog: "Erledigt. Das war der letzte geplante Schritt.")
    }
}

// MARK: - Postpone

struct PostponeStepIntent: AppIntent {

    static let title: LocalizedStringResource = "Nächsten Schritt verschieben"
    static let description = IntentDescription("Verschiebt den anstehenden Schritt um einige Minuten nach hinten oder nach vorne, auf Wunsch mit allen folgenden Schritten.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Minuten", inclusiveRange: (1, 1440), requestValueDialog: "Um wie viele Minuten?")
    var minutes: Int

    /// Later unless the phrase said otherwise, so "Nächsten Schritt
    /// verschieben" never has to ask which way.
    @Parameter(title: "Richtung", default: .later)
    var direction: StepShiftDirection

    @Parameter(title: "Folgende Schritte mitverschieben", default: true)
    var includeFollowing: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Nächsten Schritt um \(\.$minutes) Minuten \(\.$direction)") {
            \.$includeFollowing
        }
    }

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let now = Date()
        guard let current = try PlannedStepStore.currentStep(at: now) else {
            throw PlannedStepIntentError.noPlannedSteps
        }
        let step = current.step
        let instruction = IntentPhrasing.spokenInstruction(step.instruction)
        let recipeName = step.recipeName

        guard let target = PlannedStepStore.shiftedDate(of: step.date, isDue: current.isDue, minutes: minutes,
                                                        direction: direction, now: now) else {
            throw PlannedStepIntentError.dueStepCannotComeEarlier
        }
        let shiftMinutes = Int((target.timeIntervalSince(step.date) / 60).rounded())
        guard shiftMinutes != 0 else {
            throw PlannedStepIntentError.shiftedIntoPast
        }

        let followers = includeFollowing ? try PlannedStepStore.followingSteps(of: step) : []
        if !followers.isEmpty {
            switch direction {
            case .later:
                try await requestConfirmation(
                    dialog: "„\(instruction)“ und alle folgenden Schritte von \(recipeName) um \(minutes) Minuten nach hinten verschieben?"
                )
            case .earlier:
                try await requestConfirmation(
                    dialog: "„\(instruction)“ und alle folgenden Schritte von \(recipeName) um \(minutes) Minuten vorziehen?"
                )
            }
        }

        do {
            try await PlannedStepStore.shift(step, byMinutes: shiftMinutes, includeFollowing: !followers.isEmpty)
        } catch ScheduledStepShiftError.dateInPast {
            throw PlannedStepIntentError.shiftedIntoPast
        } catch {
            throw PlannedStepIntentError.couldNotSave
        }

        let when = IntentPhrasing.dateText(target, now: now)
        switch direction {
        case .later:
            return .result(dialog: "Verschoben. „\(instruction)“ für \(recipeName) ist jetzt \(when) fällig.")
        case .earlier:
            return .result(dialog: "Vorgezogen. „\(instruction)“ für \(recipeName) ist jetzt \(when) fällig.")
        }
    }
}

// MARK: - Oven time

struct OvenTimeIntent: AppIntent {

    static let title: LocalizedStringResource = "Wann in den Ofen?"
    static let description = IntentDescription("Sagt, wann das Gebäck laut Plan in den Ofen kommt.")
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        let now = Date()
        guard let step = try PlannedStepStore.nextBakingStep(at: now) else {
            throw PlannedStepIntentError.noBakingStep
        }

        let instruction = IntentPhrasing.spokenInstruction(step.instruction)
        let recipeName = step.recipeName
        let when = IntentPhrasing.dateText(step.date, now: now)

        let dialog: IntentDialog = step.date <= now
            ? "\(recipeName) kommt jetzt in den Ofen: \(instruction)."
            : "\(recipeName) kommt \(when) in den Ofen: \(instruction)."
        return .result(value: when, dialog: dialog)
    }
}
