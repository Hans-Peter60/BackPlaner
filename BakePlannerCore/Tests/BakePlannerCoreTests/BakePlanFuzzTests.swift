//
//  BakePlanFuzzTests.swift
//  BakePlannerCoreTests
//
//  Hundreds of random recipes (FUZZ_ROUNDS=3000 for thousands) — odd wording in three languages, steps of
//  no length, very long steps, substeps, windows, stored oven settings that
//  contradict the text — planned the way the app plans them. Nothing may
//  crash, and every plan keeps the invariants the simulation checks. The
//  generator is seeded, so a failure repeats with the same recipe.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Bake planning: random recipes keep the plan's invariants", .serialized)
struct BakePlanFuzzTests {

    /// SplitMix64, so every run builds the same recipes.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static let texts = [
        "Teig kneten", "Stockgare 3 Stunden", "Nach 30 Minuten falten", "Formen", "Stückgare 60 Minuten",
        "Bei 250 °C backen", "Bei 250 °C fallend auf 220 °C backen", "Mit Dampf bei 240 °C 25 Minuten backen",
        "Bei 250 °C mit Schwaden backen, Schwaden nach 10 Minuten ablassen",
        "Die ersten 15 Minuten mit Dampf bei 240 °C backen", "Nach 10 Minuten Dampf ablassen", "Dampf ablassen",
        "Backofen auf 250 °C vorheizen", "Backofen anstellen", "Im kalten Backofen bei 200 °C backen",
        "Teig im ausgeschalteten Backofen gehen lassen", "Bis zum nächsten Backen in den Kühlschrank stellen",
        "Vor dem Backen einschneiden, dann bei 230 °C backen", "Sofort auf 200 °C herunterdrehen",
        "Bei 200 °C fallend auf 250 °C backen", "Bei 250 °C fallend auf 220 °C, nach 0 Minuten zurückdrehen",
        "Bei 250 °C fallend auf 220 °C, nach 99999999999999999999 Minuten zurückdrehen",
        "Schwaden nach 99999999999999999999 Minuten ablassen", "Bei 99999999999999999999 °C backen",
        "Bake at 450°F falling to 400°F", "Preheat the oven to 230 °C", "Release the steam after 12 minutes",
        "Cuire à 240 °C, les 10 premières avec buée", "Préchauffer le four", "Évacuer la buée",
        "Auskühlen lassen", "", " ", "🍞🔥", String(repeating: "Backen ", count: 400),
        "Backofen auf 220 °C zurückdrehen", "Backvorgang ist beendet", "1.5. Schritt. Backen.",
    ]

    private func randomRecipe(using generator: inout SeededGenerator) -> [InstructionFB] {
        var instructions: [InstructionFB] = []
        let groups = Int.random(in: 1...10, using: &generator)
        for group in 1...groups {
            let substeps = Int.random(in: 0...4, using: &generator) == 0 ? Int.random(in: 1...4, using: &generator) : 0
            for sub in 0...substeps {
                let instruction = InstructionFB()
                instruction.id = UUID().uuidString
                instruction.step = substeps == 0 ? Double(group) : Double(group) + Double(sub + 1) / 10
                instruction.instruction = Self.texts.randomElement(using: &generator) ?? ""
                instruction.duration = [0, 1, 5, 10, 25, 60, 180, 720, 1440, 30_000]
                    .randomElement(using: &generator) ?? 0
                if Bool.random(using: &generator), Int.random(in: 0...3, using: &generator) == 0 {
                    let low = Int.random(in: 0...600, using: &generator)
                    instruction.minDuration = low
                    instruction.maxDuration = low + Int.random(in: -60...600, using: &generator)
                }
                if Int.random(in: 0...4, using: &generator) == 0 {
                    instruction.ovenTemperature = [nil, 0, 50, 230, 250, 400].randomElement(using: &generator) ?? nil
                    instruction.ovenFallingTemperature = [nil, 200, 260, -10].randomElement(using: &generator) ?? nil
                    instruction.ovenSteam = [nil, true, false].randomElement(using: &generator) ?? nil
                }
                if group == 1, Bool.random(using: &generator) { instruction.componentName = "Vorteig" }
                instructions.append(instruction)
            }
        }
        return instructions
    }

    @Test("Random recipes plan without crashing and keep their invariants")
    func randomRecipesKeepTheInvariants() {
        var generator = SeededGenerator(state: 20_261_117)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 18))!

        // FUZZ_ROUNDS=3000 for a long run; the default keeps the test plan quick.
        let rounds = ProcessInfo.processInfo.environment["FUZZ_ROUNDS"].flatMap(Int.init) ?? 400
        for round in 0..<rounds {
            let instructions = randomRecipe(using: &generator)
            let timed = Rational.calculateStartTimes(instructions, date)
            let prepTime = timed.map { ($0.startTime ?? 0) + $0.duration }.max() ?? 0
            let steps = timed.map {
                PlanStep(instruction: $0.instruction, step: $0.step, startTime: $0.startTime ?? 0,
                         duration: $0.duration, componentName: $0.componentName,
                         durationWindow: $0.durationWindow, oven: $0.oven)
            }
            let language = ["de", "en", "fr"].randomElement(using: &generator) ?? "de"
            let anchor: PlanAnchor = Bool.random(using: &generator) ? .finishesBy : .startsAt
            let plan = BakePlan(recipeName: "Fuzz \(round)", steps: steps, prepTime: prepTime, anchor: anchor,
                                date: date, languageCode: language, preheatTime: 15, stonePreheatTime: 45,
                                calendar: calendar, isStarterFeeding: Int.random(in: 0...9, using: &generator) == 0,
                                ovenProfile: nil)
            let context = "round \(round): \(steps.map { "\($0.step) \($0.duration) „\($0.instruction.prefix(40))“" })"

            // Everything the app touches when it shows, checks and stores a plan.
            let all = plan.allSteps
            _ = plan.issues(existingWindows: [])
            _ = plan.bakeWindow
            _ = plan.scheduledStepData(planID: UUID(), servingScale: 1)
            _ = plan.moved(to: date.addingTimeInterval(86_400))
            if round % 40 == 0 {
                // The slowest call (every candidate date is a whole plan), so only now and then.
                _ = BakePlanAdvisor.nightFreeDates(for: plan, dayStart: 6, dayEnd: 23,
                                                   allowedDates: date.addingTimeInterval(-86_400 * 14)...date.addingTimeInterval(86_400 * 14))
            }
            _ = CalendarConflicts.presenceIntervals(of: plan)

            #expect(plan.steps.allSatisfy { $0.startTime >= 0 && $0.startTime + $0.duration <= plan.totalMinutes }, "\(context)")
            #expect(all.last == plan.endStep, "\(context)")
            if let bake = plan.bakingStep {
                for generated in plan.generatedSteps where generated != plan.generatedOvenStep {
                    // Turn-down and steam release fall inside the bake.
                    #expect(generated.startTime >= bake.startTime
                            && (bake.duration == 0 || generated.startTime < bake.startTime + bake.duration),
                            "\(context): „\(generated.instruction)“ outside the bake")
                }
                if let oven = plan.generatedOvenStep {
                    #expect(oven.startTime + oven.duration == bake.startTime, "\(context)")
                }
            } else {
                #expect(plan.generatedSteps.isEmpty, "\(context): generated steps without a bake")
            }
            if plan.isStarterFeeding {
                #expect(plan.bakingStep == nil, "\(context)")
            }
            // The plan's own steps are the recipe's, only moved or with a temperature added.
            #expect(plan.scheduledSteps.count == plan.steps.count, "\(context)")
        }
    }
}
