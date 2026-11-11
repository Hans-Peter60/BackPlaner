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

        public init(index: Int, phase: Phase, minutes: Int, statedTemperature: Double? = nil) {
            self.index = index
            self.phase = phase
            self.minutes = minutes
            self.statedTemperature = statedTemperature
        }

        /// What the step's duration is written for: its own temperature or
        /// the reference.
        public var referenceTemperature: Double { statedTemperature ?? ProofTiming.referenceTemperature }
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
            return Step(index: i, phase: phase, minutes: durations[i],
                        statedTemperature: statedTemperature(in: instructions[i]))
        }
    }

    /// The proofing temperature a step names, in °C: "bei 26 °C", "at
    /// 78 °F", "24–26 °C" (the middle). Nil without one, or when the only
    /// temperature is the oven's.
    public static func statedTemperature(in instruction: String) -> Double? {
        let text = instruction.lowercased()
        let pattern = #"(?<![\d.,])(\d{1,2}(?:[.,]\d)?)(?:\s*(?:-|–|bis|to|a|à)\s*(\d{1,2}(?:[.,]\d)?))?\s*(?:°\s*([cf])?|grad|degres|degrés|degrees)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let first = number(match, 1, in: text) else { continue }
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
        public let temperature: Double
        /// What the recipe's duration is written for: the longest step's.
        public let referenceTemperature: Double
        public let source: Source
        /// Today's duration per step, by the step's index.
        public let minutesByIndex: [Int: Int]

        public var differs: Bool { minutes != plannedMinutes }

        /// "aus 3 Backvorgängen" or "aus dem Rezept, bezogen auf 22 °C".
        public func sourceText(locale: Locale = AppSettings.locale,
                               bundle: Bundle = AppSettings.localizationBundle) -> String {
            switch source {
            case .bakes(let count):
                return ProofTiming.bakesText(count, bundle: bundle)
            case .recipe:
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

    /// Every phase among `steps` at `temperature`. A phase the bake
    /// history measured (`history` newest first, the entries' facts) is
    /// estimated from those bakes as the starter diary estimates ripening;
    /// otherwise each step is scaled from its own reference temperature.
    public static func adjustments(steps: [Step], history: [BakeHistoryFacts], at temperature: Double) -> [Adjustment] {
        Phase.allCases.compactMap { phase in
            let phaseSteps = steps.filter { $0.phase == phase }
            guard !phaseSteps.isEmpty else { return nil }
            let planned = phaseSteps.reduce(0) { $0 + $1.minutes }
            let reference = referenceTemperature(of: phaseSteps)

            if let estimate = StarterRipeness.estimate(from: observations(of: phase, in: history), at: temperature) {
                let byIndex = distribute(estimate.minutes, over: phaseSteps)
                return Adjustment(phase: phase, plannedMinutes: planned,
                                  minutes: byIndex.values.reduce(0, +), temperature: temperature,
                                  referenceTemperature: reference, source: .bakes(estimate.observations),
                                  minutesByIndex: byIndex)
            }

            var byIndex = [Int: Int]()
            for step in phaseSteps {
                let factor = pow(defaultQ10, (step.referenceTemperature - temperature) / 10)
                byIndex[step.index] = factor == 1 ? step.minutes : roundedToFive(Double(step.minutes) * factor)
            }
            return Adjustment(phase: phase, plannedMinutes: planned,
                              minutes: byIndex.values.reduce(0, +), temperature: temperature,
                              referenceTemperature: reference, source: .recipe,
                              minutesByIndex: byIndex)
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
        "bruhstuck", "kochstuck", "quellstuck", "quellen", "einweichen", "autolyse", "fermentolyse",
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
    /// A rest or rise without saying which.
    private static let restPatterns = [
        "ruhen", "reifen", "gehen lassen", "aufgehen", #"\bgehen\b"#, #"\bgare\b"#, "ubergare", "vollgare", "fermentier",
        #"\brest(?:s|ing)?\b(?! of\b)"#, #"\bris(?:e|es|ing)\b"#, #"\bproof"#, #"\bprov(?:e|ing)\b"#, "ferment",
        #"\bpousse"#, #"\blever\b"#, #"\blevee\b"#, #"\brepos"#, #"\bpointer\b"#
    ]
    /// Folds happen during the bulk proof; a fold step with a duration is
    /// the rest until the next fold.
    private static let foldPatterns = ["falten", "dehnen", #"\bfold"#, "rabat", "stretch"]
    private static let prefermentPatterns = [
        "sauerteig", "vorteig", "poolish", #"\bbiga\b"#, "levain", "anstellgut", "pate fermentee",
        "pre-?ferment", #"\bsponge\b"#, #"\bstarter\b"#, "lievito", #"\bmadre\b"#
    ]
    /// Named in a step that makes the main dough, the preferment goes in.
    private static let mainDoughPatterns = ["hauptteig", "main dough", "final dough", "pate finale"]
    private static let kneadPatterns = ["knet", "knead", "petri"]
}
