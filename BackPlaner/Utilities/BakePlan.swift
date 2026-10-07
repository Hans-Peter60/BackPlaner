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
            temperature: ovenTemperature
        )
        return PlanStep(instruction: text,
                        step: bakingStep.step - 0.1,
                        startTime: bakingStep.startTime - preheatDuration,
                        duration: preheatDuration)
    }

    /// The oven temperature the generated step names: the first one stated in
    /// the baking step, else in the steps after it (a second baking phase),
    /// else in those before it ("Brot einschießen, 250 °C").
    var ovenTemperature: String? {
        guard let bakingStep, let index = steps.firstIndex(of: bakingStep) else { return nil }
        let ordered = [steps[index]] + steps[(index + 1)...] + steps[..<index].reversed()
        return ordered.lazy.compactMap { Self.ovenTemperature(in: $0.instruction) }.first
    }

    /// "Backvorgang ist beendet", always `prepTime` after the start.
    var endStep: PlanStep {
        PlanStep(instruction: AppSettings.generatedStepTexts(languageCode: languageCode).bakeEnd,
                 step: 99,
                 startTime: prepTime,
                 duration: 0)
    }

    /// The recipe's steps as they are scheduled. A preheating step of the
    /// recipe's own that names no temperature ("Backofen anstellen", as
    /// planning-example imports write it) gets the oven temperature appended,
    /// like the generated one; the stored recipe is left as it is.
    var scheduledSteps: [PlanStep] {
        guard let preheat = explicitPreheatStep,
              Self.ovenTemperature(in: preheat.instruction) == nil,
              let temperature = ovenTemperature else { return steps }
        return steps.map { step in
            guard step == preheat else { return step }
            return PlanStep(instruction: Self.ovenStartText(baseText: step.instruction, temperature: temperature),
                            step: step.step, startTime: step.startTime, duration: step.duration)
        }
    }

    /// Every step the plan writes, generated ones included.
    var allSteps: [PlanStep] {
        scheduledSteps + [generatedOvenStep].compactMap { $0 } + [endStep]
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

    /// The same plan for a different date.
    func moved(to newDate: Date) -> BakePlan {
        BakePlan(recipeName: recipeName, steps: steps, prepTime: prepTime, anchor: anchor,
                 date: newDate, languageCode: languageCode, preheatTime: preheatTime,
                 calendar: calendar)
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

    /// "Backofen anstellen (250 °C)", or the plain text without a temperature.
    static func ovenStartText(baseText: String, temperature: String?) -> String {
        guard let temperature else { return baseText }
        return "\(baseText) (\(temperature))"
    }

    /// The first oven temperature a step states: "250 °C", "250°", "250 Grad",
    /// "450 °F", "425 degrees", whatever precedes it ("Ober-/Unterhitze",
    /// "von", a bracket), or a bare number after "bei", "auf", "at" or "à".
    /// Only oven heat counts, so a dough or proofing temperature ("bei 28 °C
    /// gehen lassen") is passed over: Celsius from 100, Fahrenheit from 200.
    static func ovenTemperature(in text: String) -> String? {
        let withUnit = #"(?<!\d)(\d{2,3})\s*(?:°\s*([CcFf])?|Grad\b|degrees?\b)"#
        for match in matches(of: withUnit, in: text) {
            guard let value = Int(match[0]) else { continue }
            let fahrenheit = match[1].uppercased() == "F"
            if fahrenheit, value >= 200 { return "\(value) °F" }
            if !fahrenheit, value >= 100, value <= 300 { return "\(value) °C" }
        }
        let afterPreposition = #"(?:\bbei|\bauf|\bat|à)\s+(\d{3})(?!\d)"#
        for match in matches(of: afterPreposition, in: text) {
            if let value = Int(match[0]), value >= 100, value <= 300 { return "\(value) °C" }
        }
        return nil
    }

    /// The capture groups of every match, "" for a group that did not take part.
    private static func matches(of pattern: String, in text: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).map { group in
                Range(match.range(at: group), in: text).map { String(text[$0]) } ?? ""
            }
        }
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
        /// "250 °C", if the recipe states an oven temperature.
        let ovenTemperature: String?
    }

    /// Sets a reminder for every step. `details` gives the extra text of the
    /// recipe step at that index (the ingredients a step mixes); generated
    /// steps have none.
    func scheduleReminders(details: (Int) -> String?) -> Result {
        for (index, step) in plan.scheduledSteps.enumerated() {
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
                      finishDate: finishDate,
                      ovenTemperature: plan.ovenTemperature)
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
