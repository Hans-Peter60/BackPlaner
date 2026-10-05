//
//  BakePlan.swift
//  BackPlaner
//

import Foundation
import CoreData

/// One processing step as the planner sees it, whichever recipe model it came
/// from: an own recipe (Core Data `Instruction`) or a public one
/// (`InstructionFB`).
struct PlanStep: Equatable {
    let instruction: String
    let step: Double
    /// Minutes after the plan's start.
    let startTime: Int
    let duration: Int
}

/// How the date in the baking view is read.
enum PlanAnchor {
    /// "Starten ab": the plan starts at the date.
    case startsAt
    /// "Fertig bis": the plan is finished at the date.
    case finishesBy

    /// The picker's selection in the baking views (0 = start, 1 = finish).
    init(selection: Int) {
        self = selection == 0 ? .startsAt : .finishesBy
    }
}

/// The plan one recipe yields for one date: its steps, the two the app adds
/// (switching the oven on, the end of the bake), and when each falls.
///
/// Both baking views (own and public recipes) used to work this out each in
/// its own copy, and the public one had fallen behind: it took the last step
/// for the bake, generated a preheating step next to the recipe's own, and
/// knew neither a cold oven nor the temperature. Here it exists once.
struct BakePlan {

    let recipeName: String
    /// The recipe's steps in recipe order.
    let steps: [PlanStep]
    /// Minutes from the plan's start to the end of the bake.
    let prepTime: Int
    let anchor: PlanAnchor
    /// The date chosen in the view.
    let date: Date
    /// Language of the two generated steps.
    let languageCode: String
    var preheatTime: Int = GlobalVariables.preheatTime
    var calendar: Calendar = .current

    // MARK: Derived steps

    /// The plan's start. In "Fertig bis" mode it lies `prepTime` before the
    /// chosen date.
    var baseDate: Date {
        switch anchor {
        case .startsAt:   return date
        case .finishesBy: return calendar.date(byAdding: .minute, value: -prepTime, to: date) ?? date
        }
    }

    /// The step that puts the dough into the oven: the first one worded that
    /// way, else the last step. Baking may come in phases (covered, then
    /// uncovered), and a cool-down may follow it.
    var bakingStep: PlanStep? {
        steps.first { BakePlanValidator.isBakingStartInstruction($0.instruction) } ?? steps.last
    }

    /// A step of the recipe's own that switches the oven on. An import from a
    /// planning example has one; its duration is then the recipe's, and no
    /// step is generated.
    var explicitPreheatStep: PlanStep? {
        steps.first { BakePlanValidator.isPreheatInstruction($0.instruction) }
    }

    /// Minutes the oven needs before the bake: none for a recipe with its own
    /// preheating step or one that starts in a cold oven, else the setting.
    var preheatDuration: Int {
        guard explicitPreheatStep == nil, let bakingStep else { return 0 }
        return Self.startsInColdOven(bakingStep.instruction) ? 0 : preheatTime
    }

    /// "Backofen anstellen (250 °C)", generated when the recipe has no
    /// preheating step of its own.
    var generatedOvenStep: PlanStep? {
        guard explicitPreheatStep == nil, let bakingStep else { return nil }
        let text = Self.ovenStartText(
            baseText: AppSettings.generatedStepTexts(languageCode: languageCode).startHeating,
            bakingInstruction: bakingStep.instruction
        )
        return PlanStep(instruction: text,
                        step: bakingStep.step - 0.1,
                        startTime: bakingStep.startTime - preheatDuration,
                        duration: preheatDuration)
    }

    /// "Backvorgang ist beendet", always `prepTime` after the start.
    var endStep: PlanStep {
        PlanStep(instruction: AppSettings.generatedStepTexts(languageCode: languageCode).bakeEnd,
                 step: 99,
                 startTime: prepTime,
                 duration: 0)
    }

    /// Every step the plan writes, generated ones included.
    var allSteps: [PlanStep] {
        steps + [generatedOvenStep].compactMap { $0 } + [endStep]
    }

    /// When the oven is switched on, by the recipe's own step or the
    /// generated one.
    var ovenOnStep: PlanStep? {
        explicitPreheatStep ?? generatedOvenStep
    }

    func date(of step: PlanStep) -> Date {
        calendar.date(byAdding: .minute, value: step.startTime, to: baseDate) ?? baseDate
    }

    /// A step's offset from the date chosen in the view, which is what the
    /// reminders are set relative to.
    func reminderOffset(of step: PlanStep) -> Int {
        anchor == .startsAt ? step.startTime : step.startTime - prepTime
    }

    // MARK: Plan check

    var plannedSteps: [PlannedStep] {
        allSteps.map { PlannedStep(instruction: $0.instruction, step: $0.step, date: date(of: $0)) }
    }

    /// The oven phase: from the step that puts the dough in until the plan
    /// ends.
    var bakeWindow: BakeWindow? {
        guard let bakingStep else { return nil }
        let start = date(of: bakingStep)
        let end = date(of: endStep)
        guard end >= start else { return nil }
        return BakeWindow(recipeName: recipeName, start: start, end: end)
    }

    func issues(existingWindows: [BakeWindow]) -> [BakePlanIssue] {
        BakePlanValidator.issues(for: plannedSteps, bakeWindow: bakeWindow, existingWindows: existingWindows)
    }

    func issues(in context: NSManagedObjectContext) -> [BakePlanIssue] {
        issues(existingWindows: BakePlanValidator.scheduledBakeWindows(excluding: recipeName, in: context))
    }

    // MARK: Wording

    static func startsInColdOven(_ bakingInstruction: String) -> Bool {
        let text = bakingInstruction.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                             locale: Locale(identifier: "de_DE"))
        let coldOvenPhrases = ["kalten backofen", "kalten ofen", "nicht vorheizen",
                               "ohne vorheizen", "ohne vorzuheizen"]
        return coldOvenPhrases.contains(where: text.contains)
    }

    /// The generated step names the temperature of the baking step, if it
    /// states one. "at" covers the English baking step the import writes.
    static func ovenStartText(baseText: String, bakingInstruction: String) -> String {
        let pattern = #"(?:bei|auf|at|à|a)\s+(\d{2,3})\s*(?:°\s*C|Grad)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: bakingInstruction,
                                                range: NSRange(bakingInstruction.startIndex..., in: bakingInstruction)),
              let temperatureRange = Range(match.range(at: 1), in: bakingInstruction) else {
            return baseText
        }
        return "\(baseText) (\(bakingInstruction[temperatureRange]) °C)"
    }
}

/// Puts a `BakePlan` into effect: the reminders and the scheduled steps.
struct BakePlanScheduler {

    let plan: BakePlan
    /// Identifies the plan's reminders: the recipe's reminder id and the plan
    /// id, so two plans of one recipe never replace each other's reminders.
    let reminderID: String
    var manager = LocalNotificationManager()

    struct Result {
        /// The recipe's steps plus the generated ones.
        let reminderCount: Int
        let ovenOnDate: Date
        let finishDate: Date
    }

    /// Sets a reminder for every step. `details` gives the extra text of the
    /// recipe step at that index (the ingredients a step mixes); generated
    /// steps have none.
    func scheduleReminders(details: (Int) -> String?) -> Result {
        for (index, step) in plan.steps.enumerated() {
            _ = manager.setNotification(reminderID, step.instruction,
                                        Rational.decimalPlace(step.step, 10),
                                        plan.reminderOffset(of: step), plan.date, true,
                                        details: details(index))
        }

        if let ovenStep = plan.generatedOvenStep {
            _ = manager.setNotification(reminderID, ovenStep.instruction,
                                        Rational.decimalPlace(ovenStep.step, 10),
                                        plan.reminderOffset(of: ovenStep), plan.date, true)
        }

        let endStep = plan.endStep
        let finishDate = manager.setNotification(reminderID, endStep.instruction, "99",
                                                 plan.reminderOffset(of: endStep), plan.date, true)

        return Result(reminderCount: plan.steps.count + (plan.generatedOvenStep == nil ? 1 : 2),
                      ovenOnDate: plan.ovenOnStep.map(plan.date(of:)) ?? plan.baseDate,
                      finishDate: finishDate)
    }

    /// Writes every step of the plan as a scheduled step.
    func writeScheduledSteps(planID: UUID, in context: NSManagedObjectContext) {
        for step in plan.allSteps {
            let next = NextStep(context: context)
            next.id          = UUID()
            next.planID      = planID
            next.recipeName  = plan.recipeName
            next.instruction = step.instruction
            next.step        = step.step
            next.duration    = step.duration
            next.startTime   = step.startTime
            next.date        = plan.date(of: step)
        }
        do {
            try context.save()
        } catch {
            AppLog.planning.error("Scheduled steps could not be saved: \(error.localizedDescription)")
        }
    }

    /// Whether the recipe already has scheduled steps.
    static func hasPlan(recipeName: String, in context: NSManagedObjectContext) -> Bool {
        let request = NextStep.fetchRequest()
        request.predicate = NSPredicate(format: "recipeName == %@", recipeName)
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    /// Drops every earlier plan of a recipe, its scheduled steps and their
    /// reminders, before a replacing plan is written. The reminders are
    /// matched by identifier prefix, which the new plan's id keeps out of:
    /// cancelling runs asynchronously and would otherwise catch the reminders
    /// being created right now.
    static func removePlans(recipeName: String, reminderPrefix: String,
                            keeping planID: UUID, in context: NSManagedObjectContext) {
        let request = NextStep.fetchRequest()
        request.predicate = NSPredicate(format: "recipeName == %@", recipeName)
        if let previousSteps = try? context.fetch(request) {
            previousSteps.forEach { context.delete($0) }
            try? context.save()
        }
        NotificationActions.cancelPendingNotifications(withIdentifierPrefix: "Recipe-\(reminderPrefix)-",
                                                       excludingContaining: planID.uuidString)
    }
}
