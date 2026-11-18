//
//  ProofTiming.swift
//  BakePlannerCore
//
//  How long a bread's fermentation takes today. A recipe states its
//  proofing times for one kitchen; fermentation runs roughly two and a
//  half times as fast for every 10 °C more — the Q10 rule the starter
//  diary already uses (StarterRipeness). This file finds the steps of a
//  recipe that ferment — a preferment ripening, the bulk proof (Stockgare)
//  and the final proof (Stückgare) — and works their durations out at
//  today's room temperature: from the recipe's own durations, or, once the
//  bake history has measured how long the dough really proofed, from
//  those bakes. The same bakes also say what the recipe's durations should
//  be at the reference temperature, which is what "take the durations over
//  into the recipe" writes.
//
//  The steps are told apart by their wording in German, English and
//  French: explicit names first ("Stockgare", "final proof", "apprêt"),
//  then generic rests ("gehen lassen", "rise", "pousse") by where they
//  stand — before the shaping step they are the bulk proof, from it on
//  the final proof. Steps in the fridge, soakers and the autolyse do not
//  ferment at room temperature and stay as they are; so does everything
//  after the bake.
//

import Foundation

public enum ProofTiming {

    /// The temperature a recipe's durations are read as written for,
    /// unless a step names its own.
    public static let referenceTemperature = StarterRipeness.referenceTemperature
    /// How many times faster the dough ferments for 10 °C more.
    public static let defaultQ10 = StarterRipeness.defaultQ10
    /// Temperatures a proofing step may name; an oven is far above.
    public static let statedTemperatureRange = 15.0...40.0
    /// A step without an explicit proof word counts as a rest only from
    /// this length on: a short pause and "the rest of the flour" are none.
    public static let minimumRestMinutes = 15
    /// Today's room temperature can be set between these, in °C.
    public static let temperatureRange = 10...35
    /// What "an einem warmen Ort" without a number is taken for, until the
    /// baker says better.
    public static let assumedWarmPlaceTemperature = 26.0

    // MARK: - Phases and steps

    public enum Phase: Int, CaseIterable, Equatable, Hashable, Comparable {
        /// A preferment (Sauerteig, Poolish, Biga, Levain) ripening.
        case preferment
        /// The bulk proof (Stockgare), before shaping.
        case bulk
        /// The final proof (Stückgare), after shaping.
        case final

        public static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }

        /// The phase's name in the app's language.
        public func title(bundle: Bundle = AppSettings.localizationBundle) -> String {
            switch self {
            case .preferment: return String(localized: "Vorteig-Reife", bundle: bundle)
            case .bulk: return String(localized: "Stockgare", bundle: bundle)
            case .final: return String(localized: "Stückgare", bundle: bundle)
            }
        }
    }

    /// One fermentation step of a recipe.
    public struct Step: Equatable {
        /// The step's position among the recipe's instructions.
        public let index: Int
        public let phase: Phase
        /// The step's duration as the recipe has it.
        public let minutes: Int
        /// The temperature the step names ("bei 26 °C"), if any.
        public let statedTemperature: Double?
        /// Whether the step names a warm place without a number ("an einem
        /// warmen Ort", "im Backofen mit Licht", "im Gärschrank").
        public let warmPlace: Bool

        public init(index: Int, phase: Phase, minutes: Int, statedTemperature: Double? = nil, warmPlace: Bool = false) {
            self.index = index
            self.phase = phase
            self.minutes = minutes
            self.statedTemperature = statedTemperature
            self.warmPlace = warmPlace
        }

        /// Where the recipe puts the dough for this step, if it says: the
        /// temperature it names, or the one assumed for a warm place. Such
        /// a step does not follow the room's temperature.
        public var placeTemperature: Double? {
            statedTemperature ?? (warmPlace ? ProofTiming.assumedWarmPlaceTemperature : nil)
        }

        /// What the step's duration is written for: its place's temperature
        /// or the reference.
        public var referenceTemperature: Double { placeTemperature ?? ProofTiming.referenceTemperature }
    }

    // MARK: - Finding the steps

    /// The fermentation steps among `instructions` with their `durations`,
    /// in recipe order. Steps without a duration, in the fridge, soaking,
    /// or after the bake are left out.
    public static func steps(instructions: [String], durations: [Int]) -> [Step] {
        let count = min(instructions.count, durations.count)
        guard count > 0 else { return [] }
        let texts = (0..<count).map { fold(instructions[$0]) }

        // Nothing after the dough went into the oven ferments.
        let bakeIndex = (0..<count).first { BakePlanValidator.isBakingStartInstruction(instructions[$0]) }
        let before = 0..<(bakeIndex ?? count)

        enum Role { case none, preferment, bulk, final, rest }
        var roles = [Role](repeating: .none, count: count)
        var shapeIndex: Int?

        for i in before {
            let text = texts[i]
            if shapeIndex == nil, matches(shapePatterns, text) { shapeIndex = i }
            guard durations[i] > 0 else { continue }
            if matches(coldPatterns, text) || matches(soakerPatterns, text) { continue }
            if matches(finalPatterns, text) { roles[i] = .final; continue }
            if matches(bulkPatterns, text) { roles[i] = .bulk; continue }
            let rests = matches(restPatterns, text) || matches(foldPatterns, text)
            guard rests, durations[i] >= minimumRestMinutes else { continue }
            // The step that makes a preferment and lets it ripen; kneading
            // or naming the main dough means the preferment goes in here.
            if matches(prefermentPatterns, text), !matches(mainDoughPatterns, text), !matches(kneadPatterns, text) {
                roles[i] = .preferment
                continue
            }
            // An autolyse or soaker step without a duration has its time in
            // the rest that follows ("Autolyse: Mehl und Wasser mischen." –
            // "30 Minuten ruhen lassen."); that rest was counted as bulk proof.
            if i > 0, durations[i - 1] == 0, matches(soakerPatterns, texts[i - 1]), !matches(foldPatterns, text) { continue }
            roles[i] = .rest
        }

        // Where the bulk proof ends: at the shaping step, else at the first
        // step named as final proof, else — with several rests — at the
        // last of them.
        let genericRests = roles.indices.filter { roles[$0] == .rest }
        let boundary = shapeIndex
            ?? roles.firstIndex(of: .final)
            ?? (genericRests.count >= 2 ? genericRests.last : nil)

        return roles.indices.compactMap { i in
            let phase: Phase
            switch roles[i] {
            case .none: return nil
            case .preferment: phase = .preferment
            case .bulk: phase = .bulk
            case .final: phase = .final
            case .rest:
                if let boundary, i >= boundary { phase = .final } else { phase = .bulk }
            }
            let stated = statedTemperature(in: instructions[i])
            return Step(index: i, phase: phase, minutes: durations[i], statedTemperature: stated,
                        warmPlace: stated == nil && matches(warmPlacePatterns, texts[i]))
        }
    }

    /// The proofing temperature a step names, in °C: "bei 26 °C", "at
    /// 78 °F", "24–26 °C" (the middle). Nil without one, or when the only
    /// temperature is the oven's.
    ///
    /// The dough's or the water's temperature is no proofing temperature:
    /// "Kneten (gewünschte Teigtemperatur: ca. 28 °C) und reifen lassen" is
    /// written for the room the recipe assumes. Read as 28 °C, that step was
    /// scaled down to 22 °C on its own, and a bulk proof planned for 22 °C
    /// came out 35 minutes longer at 22 °C.
    public static func statedTemperature(in instruction: String) -> Double? {
        let text = instruction.lowercased()
        let pattern = #"(?<![\d.,])(\d{1,2}(?:[.,]\d)?)(?:\s*(?:-|–|bis|to|a|à)\s*(\d{1,2}(?:[.,]\d)?))?\s*(?:°\s*([cf])?|grad|degres|degrés|degrees)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let first = number(match, 1, in: text) else { continue }
            guard !namesDoughOrWater(text, before: match.range.location) else { continue }
            let second = number(match, 2, in: text)
            var value = second.map { ($0 + first) / 2 } ?? first
            if let unitRange = Range(match.range(at: 3), in: text), text[unitRange] == "f" {
                value = (value - 32) * 5 / 9
            }
            if statedTemperatureRange.contains(value) {
                return (value * 10).rounded() / 10
            }
        }
        return nil
    }

    /// Whether the words just before a temperature, in its own part of the
    /// sentence, make it the dough's or the water's: "Teigtemperatur: ca.
    /// 28 °C", "TT 26 °C", "Wasser mit 30 °C", "dough temperature of 78 °F",
    /// "température de pâte 25 °C". "Teigtemperatur 26 °C, bei 28 °C gehen
    /// lassen" still proofs at 28 °C.
    private static func namesDoughOrWater(_ lowercased: String, before location: Int) -> Bool {
        var leadIn = (lowercased as NSString).substring(to: location)
        if let cut = leadIn.lastIndex(where: { ",;()°".contains($0) }) {
            leadIn = String(leadIn[leadIn.index(after: cut)...])
        }
        let folded = leadIn.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        return folded.range(of: doughOrWaterPattern, options: .regularExpression) != nil
    }

    private static let doughOrWaterPattern =
        #"\b(teigtemp\w*|wassertemp\w*|schuttwasser\w*|tt|wasser\s+(mit|von)|dough\s+temp\w*|water\s+temp\w*|water\s+(at|of)|temperature\s+de\s+(la\s+)?pate|temperature\s+de\s+l'eau|eau\s+a)\b"#

    // MARK: - Today's durations

    /// Where an adjustment's minutes come from.
    public enum Source: Equatable {
        /// Scaled from the recipe's own durations.
        case recipe
        /// From this many bakes that measured the proof.
        case bakes(Int)
    }

    /// A phase's duration today.
    public struct Adjustment: Equatable {
        public let phase: Phase
        /// The phase's duration as the recipe has it, all its steps together.
        public let plannedMinutes: Int
        /// The phase's duration at `temperature`, all its steps together.
        public let minutes: Int
        /// The temperature the phase is worked out for: the one set for
        /// it, else `defaultTemperature`.
        public let temperature: Double
        /// What the recipe's duration is written for: the longest step's.
        public let referenceTemperature: Double
        public let source: Source
        /// Today's duration per step, by the step's index.
        public let minutesByIndex: [Int: Int]
        /// Where the recipe puts the dough for the phase — its longest
        /// step's place ("bei 28 °C", a warm place) — nil when it proofs at
        /// room temperature.
        public let placeTemperature: Double?
        /// Whether that place is a warm place without a number, its
        /// temperature only assumed.
        public let isAssumedPlace: Bool
        /// What the phase is worked out for unless the baker sets another
        /// temperature: its place's, else today's room temperature.
        public let defaultTemperature: Double

        public init(phase: Phase, plannedMinutes: Int, minutes: Int, temperature: Double,
                    referenceTemperature: Double, source: Source, minutesByIndex: [Int: Int],
                    placeTemperature: Double? = nil, isAssumedPlace: Bool = false, defaultTemperature: Double? = nil) {
            self.phase = phase
            self.plannedMinutes = plannedMinutes
            self.minutes = minutes
            self.temperature = temperature
            self.referenceTemperature = referenceTemperature
            self.source = source
            self.minutesByIndex = minutesByIndex
            self.placeTemperature = placeTemperature
            self.isAssumedPlace = isAssumedPlace
            self.defaultTemperature = defaultTemperature ?? temperature
        }

        public var differs: Bool { minutes != plannedMinutes }

        /// "aus 3 Backvorgängen", "aus dem Rezept, bezogen auf 22 °C", or —
        /// for a phase the recipe puts somewhere, left there — "bei 28 °C
        /// wie im Rezept" / "an einem warmen Ort, angenommen 26 °C – bitte
        /// anpassen".
        public func sourceText(locale: Locale = AppSettings.locale,
                               bundle: Bundle = AppSettings.localizationBundle) -> String {
            switch source {
            case .bakes(let count):
                return ProofTiming.bakesText(count, bundle: bundle)
            case .recipe:
                if let place = placeTemperature, temperature == place {
                    let text = BakeHistoryFacts.temperatureText(place, locale: locale)
                    return isAssumedPlace
                        ? String(localized: "an einem warmen Ort, angenommen \(text) – bitte anpassen", bundle: bundle)
                        : String(localized: "bei \(text) wie im Rezept", bundle: bundle)
                }
                let reference = BakeHistoryFacts.temperatureText(referenceTemperature, locale: locale)
                return String(localized: "aus dem Rezept, bezogen auf \(reference)", bundle: bundle)
            }
        }
    }

    /// "aus einem Backvorgang", "aus 3 Backvorgängen".
    public static func bakesText(_ count: Int, bundle: Bundle = AppSettings.localizationBundle) -> String {
        count == 1
            ? String(localized: "aus einem Backvorgang", bundle: bundle)
            : String(localized: "aus \(count) Backvorgängen", bundle: bundle)
    }

    /// Every phase among `steps` today. A phase the recipe puts
    /// somewhere — "bei 28 °C", "an einem warmen Ort", "im Backofen mit
    /// Licht" — is worked out for that place, so it stays as the recipe
    /// has it; the others for the room's `temperature`. `phaseTemperatures`
    /// overrides either for a phase: the baker without a warm place sets
    /// the Stückgare to 22 °C. Until 2.4 every phase followed the room, and
    /// a Stückgare "bei 28 °C" read 3h 30m at 22 °C for a dough that was to
    /// stand at 28 °C.
    ///
    /// In a phase at a place, its steps at no place of their own stay at
    /// the room's temperature, and the other way round. A phase the bake
    /// history measured (`history` newest first, the entries' facts) is
    /// estimated from those bakes as the starter diary estimates ripening;
    /// otherwise each step is scaled from its own reference temperature.
    public static func adjustments(steps: [Step], history: [BakeHistoryFacts], at temperature: Double,
                                   phaseTemperatures: [Phase: Double] = [:]) -> [Adjustment] {
        Phase.allCases.compactMap { phase in
            let phaseSteps = steps.filter { $0.phase == phase }
            guard !phaseSteps.isEmpty else { return nil }
            let planned = phaseSteps.reduce(0) { $0 + $1.minutes }
            let reference = referenceTemperature(of: phaseSteps)
            let longest = phaseSteps.max { $0.minutes < $1.minutes }
            let place = longest?.placeTemperature
            let isAssumed = place != nil && longest?.statedTemperature == nil
            let defaultTemperature = place ?? temperature
            let target = phaseTemperatures[phase] ?? defaultTemperature

            if let estimate = StarterRipeness.estimate(from: observations(of: phase, in: history), at: target) {
                let byIndex = distribute(estimate.minutes, over: phaseSteps)
                return Adjustment(phase: phase, plannedMinutes: planned,
                                  minutes: byIndex.values.reduce(0, +), temperature: target,
                                  referenceTemperature: reference, source: .bakes(estimate.observations),
                                  minutesByIndex: byIndex, placeTemperature: place, isAssumedPlace: isAssumed,
                                  defaultTemperature: defaultTemperature)
            }

            var byIndex = [Int: Int]()
            for step in phaseSteps {
                // A step at the phase's kind of place goes to the phase's
                // temperature; one of the other kind keeps its own: a step
                // at a place stays there, one at no place follows the room.
                let stepTarget: Double
                if (step.placeTemperature != nil) == (place != nil) {
                    stepTarget = target
                } else {
                    stepTarget = step.placeTemperature ?? temperature
                }
                let factor = pow(defaultQ10, (step.referenceTemperature - stepTarget) / 10)
                byIndex[step.index] = factor == 1 ? step.minutes : roundedToFive(Double(step.minutes) * factor)
            }
            return Adjustment(phase: phase, plannedMinutes: planned,
                              minutes: byIndex.values.reduce(0, +), temperature: target,
                              referenceTemperature: reference, source: .recipe,
                              minutesByIndex: byIndex, placeTemperature: place, isAssumedPlace: isAssumed,
                              defaultTemperature: defaultTemperature)
        }
    }

    // MARK: - The recipe's durations from the bakes

    /// What a phase's duration in the recipe should be, judged from the
    /// bakes that measured it.
    public struct RecipeDurations: Equatable {
        public let phase: Phase
        /// How many bakes measured the phase.
        public let bakes: Int
        /// The phase's duration as the recipe has it.
        public let plannedMinutes: Int
        /// The phase's duration at `referenceTemperature`, from the bakes.
        public let minutes: Int
        public let referenceTemperature: Double
        /// The duration per step, by the step's index.
        public let minutesByIndex: [Int: Int]

        public var differs: Bool { minutes != plannedMinutes }
    }

    /// For every phase the bake history measured: its duration brought to
    /// the recipe's reference temperature, to be written into the recipe.
    public static func recipeDurations(steps: [Step], history: [BakeHistoryFacts]) -> [RecipeDurations] {
        Phase.allCases.compactMap { phase in
            let phaseSteps = steps.filter { $0.phase == phase }
            guard !phaseSteps.isEmpty else { return nil }
            let reference = referenceTemperature(of: phaseSteps)
            guard let estimate = StarterRipeness.estimate(from: observations(of: phase, in: history), at: reference) else {
                return nil
            }
            let byIndex = distribute(estimate.minutes, over: phaseSteps)
            return RecipeDurations(phase: phase, bakes: estimate.observations,
                                   plannedMinutes: phaseSteps.reduce(0) { $0 + $1.minutes },
                                   minutes: byIndex.values.reduce(0, +),
                                   referenceTemperature: reference, minutesByIndex: byIndex)
        }
    }

    // MARK: - Helpers

    /// The bakes that measured `phase`, as the starter diary's
    /// observations. A bake without a room temperature counts as one at
    /// the reference temperature. Only the bulk and final proof are
    /// measured; a preferment never has observations.
    static func observations(of phase: Phase, in history: [BakeHistoryFacts]) -> [StarterRipeness.Observation] {
        history.compactMap { facts in
            let minutes: Int?
            switch phase {
            case .preferment: minutes = nil
            case .bulk: minutes = facts.bulkProofMinutes
            case .final: minutes = facts.finalProofMinutes
            }
            guard let minutes, minutes > 0 else { return nil }
            return StarterRipeness.Observation(temperature: facts.roomTemperature ?? referenceTemperature,
                                               peakMinutes: minutes)
        }
    }

    /// What a phase's durations are written for: the longest step's
    /// reference temperature.
    static func referenceTemperature(of steps: [Step]) -> Double {
        steps.max { $0.minutes < $1.minutes }?.referenceTemperature ?? referenceTemperature
    }

    /// `total` minutes shared among `steps` in proportion to their
    /// durations, each to five minutes; a single step gets the total.
    static func distribute(_ total: Int, over steps: [Step]) -> [Int: Int] {
        let planned = steps.reduce(0) { $0 + $1.minutes }
        guard planned > 0 else { return [:] }
        if steps.count == 1, let step = steps.first { return [step.index: total] }
        var result = [Int: Int]()
        for step in steps {
            result[step.index] = roundedToFive(Double(total) * Double(step.minutes) / Double(planned))
        }
        return result
    }

    static func roundedToFive(_ minutes: Double) -> Int {
        max(5, Int((minutes / 5).rounded()) * 5)
    }

    private static func number(_ match: NSTextCheckingResult, _ group: Int, in text: String) -> Double? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }

    // MARK: - Words

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }

    private static func matches(_ patterns: [String], _ text: String) -> Bool {
        patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// Shaping ends the bulk proof.
    private static let shapePatterns = [
        "formen", "wirken", "aufarbeiten", "rundschleifen",
        #"\bshap(?:e|ed|ing)\b"#, "preshape", "pre-shape",
        "faconn", #"\bbouler\b"#, "mettre en forme", "mise en forme"
    ]
    /// Whether a step happens in the fridge — a cold retard, "über Nacht
    /// kühl stellen". The recipe facets read it as a long rest that asks
    /// nothing of the baker.
    public static func isColdStep(_ instruction: String) -> Bool {
        matches(coldPatterns, fold(instruction))
    }

    /// In the fridge the room temperature does not matter.
    private static let coldPatterns = [
        "kuhlschrank", "kuhl", "kalt", "fridge", "refrigerat", #"\bcold\b"#, "retard", "frigo", "froid", "au frais"
    ]
    /// Soaking and the autolyse are no fermentation.
    private static let soakerPatterns = [
        "bruhstuck", "kochstuck", "quellstuck", "quellen", "einweichen", "autolys", "fermentolyse",
        "soaker", "scald", "tangzhong", #"\bsoak"#, "trempage"
    ]
    private static let finalPatterns = [
        "stuckgare", "stuck-gare", "garkorb", "garform",
        "final proof", "final rise", "final ferment", "second rise", "second proof", "banneton",
        #"\bappret"#, "deuxieme pousse", "seconde pousse", "deuxieme levee", "seconde levee"
    ]
    private static let bulkPatterns = [
        "stockgare", "stock-gare", "teigruhe",
        #"\bbulk\b"#, "first rise", "first proof", "first ferment", "primary ferment",
        "pointage", "premiere pousse", "premiere levee"
    ]
    /// A rest or rise without saying which. "Anspringen lassen" is the warm
    /// start of a bulk proof that goes on in the fridge. The translations of
    /// the public recipes say "let it ripen", "laisser mûrir" and "let it
    /// sit", and "Autolysis" for the autolyse.
    private static let restPatterns = [
        "ruhen", "reifen", "anspring", "gehen lassen", #"\bripen"#, #"\bmuri"#,
        #"\b(?:let|leave)(?: it| them| the dough)? (?:sit|stand)\b"#, "aufgehen", #"\bgehen\b"#, #"\bgare\b"#, "ubergare", "vollgare", "fermentier",
        #"\brest(?:s|ing)?\b(?! of\b)"#, #"\bris(?:e|es|ing)\b"#, #"\bproof"#, #"\bprov(?:e|ing)\b"#, "ferment",
        #"\bpousse"#, #"\blever\b"#, #"\blevee\b"#, #"\brepos"#, #"\bpointer\b"#
    ]
    /// Folds happen during the bulk proof; a fold step with a duration is
    /// the rest until the next fold.
    /// French translations write "Étirer et plier" / "replier" as often as
    /// "rabattre"; without them the folds of a French recipe were no part of
    /// its bulk proof, which then read 45 minutes instead of 3h 15m.
    private static let foldPatterns = ["falten", "dehnen", #"\bfold"#, "rabat", "stretch",
                                       #"\betir"#, #"\b(?:re)?pli(?:er|ez|e|es|age|ages)?\b"#]
    private static let prefermentPatterns = [
        "sauerteig", #"\bsourdough\b"#, "vorteig", "poolish", #"\bbiga\b"#, "levain", "anstellgut", "pate fermentee",
        "pre-?ferment", #"\bsponge\b"#, #"\bstarter\b"#, "lievito", #"\bmadre\b"#
    ]
    /// Named in a step that makes the main dough, the preferment goes in.
    private static let mainDoughPatterns = ["hauptteig", "main dough", "final dough", "pate finale"]
    private static let kneadPatterns = ["knet", "knead", "petri"]
    /// A warm place without a number, on the folded text.
    private static let warmPlacePatterns = [
        "warmen ort", "warmen platz", "warm stell", "warm gestellt", "warm halten", "an einem warmen",
        "garschrank", "garbox", "garkasten", "auf der heizung", "neben der heizung",
        #"ofen mit (eingeschaltete[mn]? )?(licht|lampe)"#, "eingeschalteter lampe", "eingeschaltetem licht",
        #"ausgeschaltete[nm]? (back)?ofen"#,
        "warm place", "warm spot", "proofing box", "proofer", #"oven with the light"#, "oven light",
        "endroit chaud", "endroit tiede", "etuve", "four eteint", "four avec la lumiere", "lumiere du four"
    ]
}
