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

    /// Minutes into the bake at which the heat is turned down when the recipe
    /// says that it falls but not when: the ten minutes after which bakers
    /// release the steam.
    static let defaultTurnDownMinutes = 10

    /// "Backofen auf 220 °C zurückdrehen, Dampf ablassen", generated when the
    /// bake states a falling temperature ("250 °C fallend auf 220 °C"). The
    /// recipe knew the second temperature all along; without this step
    /// nobody was reminded of it. It falls at the minute the step names,
    /// else ten minutes into the bake, and only while the bake still runs.
    var generatedTurnDownStep: PlanStep? {
        guard let bakingStep, let index = steps.firstIndex(of: bakingStep) else { return nil }

        // The same order the oven temperature is looked for in.
        let ordered = [steps[index]] + steps[(index + 1)...] + steps[..<index].reversed()
        guard let drop = ordered.lazy.compactMap({ Self.temperatureDrop(in: $0.instruction) }).first else { return nil }
        guard bakingStep.duration <= 0 || drop.afterMinutes < bakingStep.duration else { return nil }

        let texts = AppSettings.generatedStepTexts(languageCode: languageCode)
        let format = drop.withSteam ? texts.turnDownWithSteam : texts.turnDown
        return PlanStep(instruction: String(format: format, drop.temperature),
                        step: bakingStep.step + 0.1,
                        startTime: bakingStep.startTime + drop.afterMinutes,
                        duration: 0)
    }

    /// Whether a text is a turn-down step the plan generated, in any of the
    /// languages it can be stored in. Generated steps live only in the plan,
    /// never in the recipe, so whoever compares the two has to leave them
    /// out — as "Geplante Schritte" does for the oven and finish steps.
    static func isTurnDownInstruction(_ instruction: String) -> Bool {
        for language in ["de", "en", "fr"] {
            let texts = AppSettings.generatedStepTexts(languageCode: language)
            for format in [texts.turnDown, texts.turnDownWithSteam] {
                let parts = format.components(separatedBy: "%@")
                guard parts.count == 2 else { continue }
                if instruction.hasPrefix(parts[0]), instruction.hasSuffix(parts[1]) { return true }
            }
        }
        return false
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
        scheduledSteps + [generatedOvenStep, generatedTurnDownStep].compactMap { $0 } + [endStep]
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
        ovenTemperatures(in: text).first?.text
    }

    /// An oven temperature as a step states it, and where in the text.
    private struct OvenTemperature {
        let value: Int
        let fahrenheit: Bool
        let location: Int
        var text: String { "\(value) °\(fahrenheit ? "F" : "C")" }
    }

    /// Every oven temperature a step states, in reading order. Those with a
    /// unit come first so the first one wins over a bare number after "bei".
    private static func ovenTemperatures(in text: String) -> [OvenTemperature] {
        var found: [OvenTemperature] = []

        let withUnit = #"(?<!\d)(\d{2,3})\s*(?:°\s*([CcFf])?|Grad\b|degrees?\b)"#
        for match in matches(of: withUnit, in: text) {
            guard let value = Int(match.groups[0]) else { continue }
            let fahrenheit = match.groups[1].uppercased() == "F"
            if fahrenheit, value >= 200 {
                found.append(OvenTemperature(value: value, fahrenheit: true, location: match.location))
            } else if !fahrenheit, value >= 100, value <= 300 {
                found.append(OvenTemperature(value: value, fahrenheit: false, location: match.location))
            }
        }
        guard found.isEmpty else { return found }

        let afterPreposition = #"(?:\bbei|\bauf|\bat|à)\s+(\d{3})(?!\d)"#
        for match in matches(of: afterPreposition, in: text) {
            if let value = Int(match.groups[0]), value >= 100, value <= 300 {
                found.append(OvenTemperature(value: value, fahrenheit: false, location: match.location))
            }
        }
        return found
    }

    /// A bake whose heat falls: the lower temperature, the minute into the
    /// bake at which to turn down, and whether steam is released with it.
    ///
    /// A second temperature only counts as a drop when it is lower than the
    /// first and is not the convection figure given alongside ("230 °C
    /// Ober-/Unterhitze, Umluft 210 °C"). "Ohne Dampf" is no steam.
    static func temperatureDrop(in text: String) -> (temperature: String, afterMinutes: Int, withSteam: Bool)? {
        let temperatures = ovenTemperatures(in: text)
        guard let first = temperatures.first,
              let lower = temperatures.dropFirst().first(where: { $0.value < first.value && $0.fahrenheit == first.fahrenheit })
        else { return nil }

        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        let leadIn = String(folded.prefix(lower.location).suffix(40))
        let convectionWords = ["umluft", "heissluft", "heißluft", "fan", "convection", "tournante"]
        guard !convectionWords.contains(where: leadIn.contains) else { return nil }

        let steamWords = ["dampf", "schwaden", "steam", "buee", "vapeur"]
        let noSteamPhrases = ["ohne dampf", "ohne schwaden", "without steam", "sans buee", "sans vapeur"]
        let withSteam = steamWords.contains(where: folded.contains) && !noSteamPhrases.contains(where: folded.contains)

        return (lower.text, minutesBeforeTurningDown(in: folded) ?? defaultTurnDownMinutes, withSteam)
    }

    /// "nach 10 Minuten", "after 15 min", "après 10 minutes", or "10 Minuten
    /// anbacken, dann …" / "for 15 minutes, then …": the minute at which the
    /// heat is turned down, if the step says.
    private static func minutesBeforeTurningDown(in foldedText: String) -> Int? {
        let patterns = [
            #"(?:nach|after|apres)\s+(?:ca\.?\s*|etwa\s+|about\s+|environ\s+)?(\d{1,3})\s*(?:min\b|min\.|minuten|minutes?)"#,
            #"(\d{1,3})\s*(?:min\b|min\.|minuten|minutes?)\s*(?:anbacken|lang|,)?\s*(?:dann|danach|then|puis|anschliessend)"#
        ]
        for pattern in patterns {
            if let match = matches(of: pattern, in: foldedText).first, let minutes = Int(match.groups[0]), minutes > 0 {
                return minutes
            }
        }
        return nil
    }

    private struct Match {
        /// The capture groups, "" for one that did not take part.
        let groups: [String]
        /// Where the whole match begins, as a character offset.
        let location: Int
    }

    private static func matches(of pattern: String, in text: String) -> [Match] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            let groups = (1..<match.numberOfRanges).map { group in
                Range(match.range(at: group), in: text).map { String(text[$0]) } ?? ""
            }
            let location = Range(match.range, in: text).map { text.distance(from: text.startIndex, to: $0.lowerBound) } ?? 0
            return Match(groups: groups, location: location)
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

        let generatedSteps = [plan.generatedOvenStep, plan.generatedTurnDownStep].compactMap { $0 }
        for generated in generatedSteps {
            _ = manager.setNotification(reminderID, generated.instruction,
                                        Rational.decimalPlace(generated.step, 10),
                                        plan.reminderOffset(of: generated), plan.date, true)
        }

        let endStep = plan.endStep
        let finishDate = manager.setNotification(reminderID, endStep.instruction, "99",
                                                 plan.reminderOffset(of: endStep), plan.date, true)

        return Result(reminderCount: plan.steps.count + generatedSteps.count + 1,
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
