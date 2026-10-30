//
//  BakePlan.swift
//  BackPlaner
//

import BakePlannerCore
import Foundation

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

    /// Minutes from the plan's start to its end: the recipe's `prepTime`, but
    /// never less than the end of its last step. A stored total that fell
    /// behind the steps would otherwise put "Backvorgang ist beendet" into
    /// the middle of the bake.
    var totalMinutes: Int {
        max(prepTime, steps.map { $0.startTime + $0.duration }.max() ?? 0)
    }

    /// The plan's start. In "Fertig bis" mode it lies `totalMinutes` before
    /// the chosen date.
    var baseDate: Date {
        switch anchor {
        case .startsAt:   return date
        case .finishesBy: return calendar.date(byAdding: .minute, value: -totalMinutes, to: date) ?? date
        }
    }

    /// The step that puts the dough into the oven: the first one worded that
    /// way, else the last step — provided the recipe uses an oven at all.
    /// Baking may come in phases (covered, then uncovered), and a cool-down
    /// may follow it. Feeding a starter ("Anstellgut, Mehl und Wasser
    /// mischen, bei 26 °C reifen lassen") names no bake, no preheating and
    /// no oven temperature; taken for a bake, its last step used to switch
    /// the oven on alongside the first.
    var bakingStep: PlanStep? {
        if let worded = steps.first(where: { BakePlanValidator.isBakingStartInstruction($0.instruction) }) {
            return worded
        }
        return BakePlanValidator.usesOven(steps.map(\.instruction)) ? steps.last : nil
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
    ///
    /// A recipe that releases the steam in a step of its own ("Bei 250 °C
    /// fallend auf 220 °C mit Dampf backen", then "Dampf ablassen" twenty
    /// minutes later) has said when the steam goes; the heat is turned down
    /// as the loaf goes in, with the steam still in the oven. Its generated
    /// step names no steam and, unless the bake says otherwise, falls at the
    /// start of the bake.
    var generatedTurnDownStep: PlanStep? {
        guard let bakingStep, let index = steps.firstIndex(of: bakingStep) else { return nil }

        // The same order the oven temperature is looked for in.
        let ordered = [steps[index]] + steps[(index + 1)...] + steps[..<index].reversed()
        guard let drop = ordered.lazy.compactMap({ Self.temperatureDrop(in: $0.instruction) }).first else { return nil }

        let recipeReleasesSteam = steps[(index + 1)...].contains { Self.isSteamReleaseInstruction($0.instruction) }
        let afterMinutes = drop.afterMinutes ?? (recipeReleasesSteam ? 0 : Self.defaultTurnDownMinutes)
        guard bakingStep.duration <= 0 || afterMinutes < bakingStep.duration else { return nil }

        let texts = AppSettings.generatedStepTexts(languageCode: languageCode)
        let format = drop.withSteam && !recipeReleasesSteam ? texts.turnDownWithSteam : texts.turnDown
        return PlanStep(instruction: String(format: format, drop.temperature),
                        step: bakingStep.step + 0.1,
                        startTime: bakingStep.startTime + afterMinutes,
                        duration: 0)
    }

    /// Whether a step of the recipe's own lets the steam out of the oven:
    /// "Dampf ablassen", "Schwaden abziehen lassen", "Release the steam",
    /// "Évacuer la buée". The bake itself ("mit Dampf backen") is not one.
    static func isSteamReleaseInstruction(_ instruction: String) -> Bool {
        let text = instruction.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                       locale: Locale(identifier: "de_DE"))
        guard steamWords.contains(where: text.contains) else { return false }
        return steamReleaseWords.contains(where: text.contains)
    }

    private static let steamWords = ["dampf", "schwaden", "steam", "buee", "vapeur"]
    private static let steamReleaseWords = ["ablass", "abzieh", "entweich", "rauslass", "herauslass",
                                            "release", "let out", "let the steam", "drain", "remove the steam",
                                            "evacu", "echapper"]

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

    /// "Backvorgang ist beendet", `totalMinutes` after the start.
    var endStep: PlanStep {
        PlanStep(instruction: AppSettings.generatedStepTexts(languageCode: languageCode).bakeEnd,
                 step: 99,
                 startTime: totalMinutes,
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
        anchor == .startsAt ? step.startTime : step.startTime - totalMinutes
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

        // Not a quantity: "auf 150 g auffrischen", "à 100 ml" are no heat.
        let afterPreposition = #"(?:\bbei|\bauf|\bat|à)\s+(\d{3})(?!\d)(?!\s*(?:g|kg|ml|cl|l|gramm|grams?|lit(?:er|re)s?)\b)(?!\s*%)"#
        for match in matches(of: afterPreposition, in: text) {
            if let value = Int(match.groups[0]), value >= 100, value <= 300 {
                found.append(OvenTemperature(value: value, fahrenheit: false, location: match.location))
            }
        }
        return found
    }

    /// A bake whose heat falls: the lower temperature, the minute into the
    /// bake at which to turn down (nil when the step does not say), and
    /// whether steam is released with it.
    ///
    /// A second temperature only counts as a drop when it is lower than the
    /// first and is not the convection figure given alongside ("230 °C
    /// Ober-/Unterhitze, Umluft 210 °C"). "Ohne Dampf" is no steam, and
    /// neither is steam the step lets out at some other minute ("Den Ofen
    /// sofort auf 220 °C herunterdrehen. Den Dampf nach 20 Minuten
    /// ablassen."): that release is its own moment, not the turn-down's.
    static func temperatureDrop(in text: String) -> (temperature: String, afterMinutes: Int?, withSteam: Bool)? {
        let temperatures = ovenTemperatures(in: text)
        guard let first = temperatures.first,
              let lower = temperatures.dropFirst().first(where: { $0.value < first.value && $0.fahrenheit == first.fahrenheit })
        else { return nil }

        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        let leadIn = String(folded.prefix(lower.location).suffix(40))
        let convectionWords = ["umluft", "heissluft", "heißluft", "fan", "convection", "tournante"]
        guard !convectionWords.contains(where: leadIn.contains) else { return nil }

        let afterMinutes = minutesBeforeTurningDown(in: folded, lowerTemperatureAt: lower.location)

        let noSteamPhrases = ["ohne dampf", "ohne schwaden", "without steam", "sans buee", "sans vapeur"]
        var withSteam = steamWords.contains(where: folded.contains) && !noSteamPhrases.contains(where: folded.contains)
        if withSteam, let releaseMinutes = steamReleaseMinutes(in: folded), releaseMinutes != afterMinutes {
            withSteam = false
        }

        return (lower.text, afterMinutes, withSteam)
    }

    /// The minute at which the heat is turned down, if the step says. Read
    /// from the sentence that names the lower temperature: "sofort" /
    /// "immediately" / "immédiatement" there means as the loaf goes in;
    /// "nach 10 Minuten", "after 15 min", "après 10 minutes", or "10
    /// Minuten anbacken, dann …" / "for 15 minutes, then …" name the minute.
    /// Only when that sentence is silent do the others count, and never one
    /// about the steam — "Den Dampf nach 20 Minuten ablassen" times the
    /// steam, not the heat.
    private static func minutesBeforeTurningDown(in foldedText: String, lowerTemperatureAt location: Int) -> Int? {
        let sentences = Self.sentences(of: foldedText)
        let dropSentence = sentences.first { $0.range.contains(location) } ?? sentences.last

        if let dropSentence {
            if immediatelyWords.contains(where: dropSentence.text.contains) { return 0 }
            if let minutes = statedMinutes(in: dropSentence.text) { return minutes }
        }
        for sentence in sentences where sentence.range != dropSentence?.range {
            guard !steamWords.contains(where: sentence.text.contains) else { continue }
            if let minutes = statedMinutes(in: sentence.text) { return minutes }
        }
        return nil
    }

    /// The minute at which a step says it lets the steam out, when it says
    /// so in a sentence of its own.
    private static func steamReleaseMinutes(in foldedText: String) -> Int? {
        for sentence in sentences(of: foldedText) {
            guard steamWords.contains(where: sentence.text.contains),
                  steamReleaseWords.contains(where: sentence.text.contains) else { continue }
            if immediatelyWords.contains(where: sentence.text.contains) { return 0 }
            if let minutes = statedMinutes(in: sentence.text) { return minutes }
        }
        return nil
    }

    // Not "direkt": "direkt auf den Stein einschießen" places the loaf, not
    // the moment the heat is turned down.
    private static let immediatelyWords = ["sofort", "immediately", "right away", "straight away",
                                           "immediatement", "aussitot", "tout de suite"]

    private static func statedMinutes(in foldedSentence: String) -> Int? {
        let patterns = [
            #"(?:nach|after|apres)\s+(?:ca\.?\s*|etwa\s+|about\s+|environ\s+)?(\d{1,3})\s*(?:min\b|min\.|minuten|minutes?)"#,
            #"(\d{1,3})\s*(?:min\b|min\.|minuten|minutes?)\s*(?:anbacken|lang|,)?\s*(?:dann|danach|then|puis|anschliessend)"#
        ]
        for pattern in patterns {
            if let match = matches(of: pattern, in: foldedSentence).first, let minutes = Int(match.groups[0]), minutes > 0 {
                return minutes
            }
        }
        return nil
    }

    /// The text split at sentence ends, each with the character range it
    /// covers in the text; "1.5" does not end a sentence.
    private static func sentences(of text: String) -> [(text: String, range: Range<Int>)] {
        var result: [(text: String, range: Range<Int>)] = []
        var start = 0
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            let endsSentence: Bool
            switch character {
            case ";", "!", "?", "\n":
                endsSentence = true
            case ".":
                let next = index + 1 < characters.count ? characters[index + 1] : " "
                endsSentence = !next.isNumber
            default:
                endsSentence = false
            }
            if endsSentence {
                result.append((String(characters[start...index]), start..<(index + 1)))
                start = index + 1
            }
        }
        if start < characters.count {
            result.append((String(characters[start...]), start..<characters.count))
        }
        return result
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
