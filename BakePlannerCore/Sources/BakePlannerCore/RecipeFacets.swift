//
//  RecipeFacets.swift
//  BakePlannerCore
//
//  What a recipe is like, read from its steps and ingredients, for the
//  filters and collections of the recipe list: how long it takes and how
//  much of that is work, whether it fits "set up in the evening, bake in
//  the morning", what raises it, which grains, the dough yield, and the
//  equipment its steps mention. Pure reading; nothing is stored.
//

import Foundation

public struct RecipeFacets: Equatable, Sendable {

    /// From start to the end of the bake.
    public enum Duration: String, CaseIterable, Identifiable, Sendable {
        /// Under four hours.
        case short
        /// Four to twelve hours.
        case halfDay
        /// Twelve to thirty hours: a night in it.
        case overnight
        /// Longer still.
        case multiDay
        public var id: Self { self }
    }

    /// How the recipe sits in a day. A recipe can fit more than one.
    public enum DayFlow: String, CaseIterable, Identifiable, Sendable {
        /// A rest of six hours or more, after which only shaping, the oven
        /// and the bake remain — within three hours of wall-clock time.
        case eveningToMorning
        /// Ten hours at most, no rest of six hours or more.
        case sameDay
        /// Two hours at most from start to finish.
        case quick
        public var id: Self { self }
    }

    public enum Leavening: String, CaseIterable, Identifiable, Sendable {
        case sourdough
        case lievitoMadre
        case yeast
        /// Sourdough or lievito madre together with yeast.
        case mixed
        case none
        public var id: Self { self }
    }

    public enum Equipment: String, CaseIterable, Identifiable, Sendable {
        case bakingStone
        case loafTin
        case proofingBasket
        case dutchOven
        public var id: Self { self }
    }

    public enum DoughYieldBand: String, CaseIterable, Identifiable, Sendable {
        /// Under TA 165.
        case firm
        /// TA 165 to under 180.
        case medium
        /// TA 180 and more.
        case soft
        public var id: Self { self }
    }

    public static let quickMinutes = 120
    public static let sameDayMinutes = 600
    public static let longRestMinutes = 360
    public static let morningBudgetMinutes = 180
    /// Hans-Peter's figure (11 Nov 2026): half an hour of hands-on time is
    /// "little work" for a bread that otherwise rests and bakes on its own.
    public static let lowWorkMinutes = 30

    public let totalMinutes: Int
    /// Minutes of mixing, folding and shaping — what the baker does.
    public let activeMinutes: Int
    public let longestRestMinutes: Int
    public let duration: Duration
    public let dayFlows: Set<DayFlow>
    public let leavening: Leavening
    /// Each grain's share of the recipe's flour, 0...1.
    public let grainShares: [FlourSubstitution.Grain: Double]
    public let wholeGrainShare: Double
    /// The dough yield (TA), when the ingredients allow working it out.
    public let doughYield: Double?
    public let equipment: Set<Equipment>

    public init(totalMinutes: Int, activeMinutes: Int, longestRestMinutes: Int, duration: Duration,
                dayFlows: Set<DayFlow>, leavening: Leavening, grainShares: [FlourSubstitution.Grain: Double],
                wholeGrainShare: Double, doughYield: Double?, equipment: Set<Equipment>) {
        self.totalMinutes = totalMinutes
        self.activeMinutes = activeMinutes
        self.longestRestMinutes = longestRestMinutes
        self.duration = duration
        self.dayFlows = dayFlows
        self.leavening = leavening
        self.grainShares = grainShares
        self.wholeGrainShare = wholeGrainShare
        self.doughYield = doughYield
        self.equipment = equipment
    }

    public var isLowWork: Bool { totalMinutes > 0 && activeMinutes <= Self.lowWorkMinutes }

    public func share(of grain: FlourSubstitution.Grain) -> Double {
        grainShares[grain] ?? 0
    }

    /// The grain with the largest share, when there is flour at all.
    public var mainGrain: FlourSubstitution.Grain? {
        grainShares.max { $0.value < $1.value || ($0.value == $1.value && $0.key.rawValue > $1.key.rawValue) }?.key
    }

    public var doughYieldBand: DoughYieldBand? {
        guard let doughYield else { return nil }
        if doughYield < 165 { return .firm }
        if doughYield < 180 { return .medium }
        return .soft
    }

    // MARK: Reading a recipe

    public static func compute(_ recipe: RecipeExportData,
                               starterYields: DoughComposition.StarterYields = .stored) -> RecipeFacets {
        let steps = timedSteps(recipe.instructions)
        let totalMinutes = steps.map { $0.start + $0.duration }.max() ?? 0

        var activeMinutes = 0
        var longestRest = 0
        for step in steps {
            switch step.kind {
            case .mix, .fold, .shape:
                activeMinutes += step.duration
            case .rest:
                longestRest = max(longestRest, step.duration)
            case .other:
                if step.isCold || step.duration >= 60 {
                    longestRest = max(longestRest, step.duration)
                } else {
                    activeMinutes += step.duration
                }
            case .oven, .bake:
                break
            }
        }

        let duration: Duration
        switch totalMinutes {
        case ..<240: duration = .short
        case ..<720: duration = .halfDay
        case ...1800: duration = .overnight
        default: duration = .multiDay
        }

        var dayFlows: Set<DayFlow> = []
        if totalMinutes > 0, totalMinutes <= quickMinutes { dayFlows.insert(.quick) }
        if totalMinutes > 0, totalMinutes <= sameDayMinutes, longestRest < longRestMinutes { dayFlows.insert(.sameDay) }
        if let restEnd = steps.filter({ $0.isLongRest }).map({ $0.start + $0.duration }).max() {
            let remaining = totalMinutes - restEnd
            let after = steps.filter { $0.start >= restEnd && $0.duration > 0 }
            let restsAgain = after.contains { ($0.kind == .rest || $0.isCold) && $0.duration >= 90 }
            if remaining > 0, remaining <= morningBudgetMinutes, !restsAgain {
                dayFlows.insert(.eveningToMorning)
            }
        }

        return RecipeFacets(totalMinutes: totalMinutes,
                            activeMinutes: activeMinutes,
                            longestRestMinutes: longestRest,
                            duration: duration,
                            dayFlows: dayFlows,
                            leavening: leavening(of: recipe),
                            grainShares: grainShares(of: recipe).shares,
                            wholeGrainShare: grainShares(of: recipe).wholeGrain,
                            doughYield: DoughComposition.compute(DoughComposition.components(of: recipe),
                                                                 starterYields: starterYields)?.doughYield,
                            equipment: equipment(in: recipe.instructions.map(\.instruction)))
    }

    /// A step with its place on the clock and what kind of step it is.
    struct TimedStep {
        let start: Int
        let duration: Int
        let kind: PlanTimelineKind
        let isCold: Bool

        var isLongRest: Bool {
            (kind == .rest || isCold || (kind == .other && duration >= 60)) && duration >= RecipeFacets.longRestMinutes
        }
    }

    /// The steps on the clock: by their stored start times, or one after the
    /// other when a recipe never had them worked out (a fresh import, a
    /// formula).
    static func timedSteps(_ instructions: [RecipeExportInstruction]) -> [TimedStep] {
        let ordered = instructions.sorted { $0.step < $1.step }
        let sequential = ordered.count > 1 && ordered.allSatisfy { $0.startTime == 0 }
        var clock = 0
        return ordered.map { instruction in
            let start = sequential ? clock : max(0, instruction.startTime)
            let duration = max(0, instruction.duration)
            clock = start + duration
            return TimedStep(start: start, duration: duration,
                             kind: PlanTimelineLane.kind(of: instruction.instruction, duration: duration),
                             isCold: ProofTiming.isColdStep(instruction.instruction))
        }
    }

    static func leavening(of recipe: RecipeExportData) -> Leavening {
        var sourdough = false
        var lievitoMadre = false
        var yeast = false
        // A component called "Sauerteig" or "Poolish" says what it is even
        // when its starter line is named loosely ("ASG", "vom letzten Mal").
        let names = recipe.components.map(\.name) + recipe.components.flatMap(\.ingredients).map(\.name)
        for name in names {
            switch DoughComposition.classify(name) {
            case .starter(.sourdough): sourdough = true
            case .starter(.lievitoMadre): lievitoMadre = true
            case .starter(.pateFermentee), .starter(.biga), .starter(.poolish): yeast = true
            default: break
            }
            if DoughComposition.yeastKind(name) != nil { yeast = true }
        }
        switch (sourdough || lievitoMadre, yeast) {
        case (true, true): return .mixed
        case (true, false): return sourdough ? .sourdough : .lievitoMadre
        case (false, true): return .yeast
        case (false, false): return .none
        }
    }

    static func grainShares(of recipe: RecipeExportData) -> (shares: [FlourSubstitution.Grain: Double], wholeGrain: Double) {
        var grams: [FlourSubstitution.Grain: Double] = [:]
        var wholeGrain = 0.0
        var flour = 0.0
        for ingredient in recipe.components.flatMap(\.ingredients) {
            guard let found = FlourSubstitution.recognize(ingredient.name) else { continue }
            let weight = ingredient.normWeight > 0 ? ingredient.normWeight : ingredient.weight
            guard weight > 0 else { continue }
            flour += weight
            grams[found.grain, default: 0] += weight
            if found.isWholeGrain { wholeGrain += weight }
        }
        guard flour > 0 else { return ([:], 0) }
        return (grams.mapValues { $0 / flour }, wholeGrain / flour)
    }

    static func equipment(in instructions: [String]) -> Set<Equipment> {
        var found: Set<Equipment> = []
        if BakePlan.usesBakingStone(instructions) { found.insert(.bakingStone) }
        let texts = instructions.map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
                .replacingOccurrences(of: "ß", with: "ss")
        }
        func mentions(_ words: [String]) -> Bool {
            texts.contains { text in words.contains(where: text.contains) }
        }
        if mentions(["kastenform", "kasten ", "in die kasten", "in der kasten", "loaf tin", "loaf pan", "bread tin",
                     "moule a cake", "moule a pain", "dans le moule"]) {
            found.insert(.loafTin)
        }
        if mentions(["garkorb", "garkorbchen", "brotform", "banneton", "proofing basket", "proving basket", "brotform"]) {
            found.insert(.proofingBasket)
        }
        if mentions(["gusseis", "topf", "brater", "dutch oven", "cast iron", "cocotte"]) {
            found.insert(.dutchOven)
        }
        return found
    }
}
