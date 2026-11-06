//
//  ProofTimingTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("A bread's fermentation steps and their durations today")
struct ProofTimingTests {

    private typealias Step = ProofTiming.Step

    private func steps(_ recipe: [(String, Int)]) -> [Step] {
        ProofTiming.steps(instructions: recipe.map(\.0), durations: recipe.map(\.1))
    }

    // MARK: Finding the steps

    @Test("A German sourdough: preferment, bulk with its temperature, final; nothing after the bake")
    func germanSourdough() {
        let found = steps([
            ("Sauerteig: Anstellgut, Mehl und Wasser verrühren und 12 Stunden bei Raumtemperatur reifen lassen.", 720),
            ("Hauptteig: alle Zutaten 8 Minuten kneten.", 10),
            ("Stockgare: 3 Stunden bei 24 °C, dabei nach 30 und 60 Minuten dehnen und falten.", 180),
            ("Teig rundwirken und in das Gärkörbchen legen.", 0),
            ("Stückgare 60 Minuten.", 60),
            ("Backofen auf 250 °C vorheizen.", 0),
            ("Brot 45 Minuten bei 250 °C fallend auf 220 °C backen.", 45),
            ("Auf einem Gitter auskühlen lassen.", 60)
        ])
        #expect(found == [
            Step(index: 0, phase: .preferment, minutes: 720),
            Step(index: 2, phase: .bulk, minutes: 180, statedTemperature: 24),
            Step(index: 4, phase: .final, minutes: 60)
        ])
    }

    @Test("Generic rests are the bulk proof before shaping and the final proof from it on")
    func genericRestsByPosition() {
        let found = steps([
            ("Mix all ingredients and knead for 10 minutes.", 10),
            ("Let the dough rise for 90 minutes.", 90),
            ("Shape into a boule.", 5),
            ("Let it rise for 60 minutes.", 60),
            ("Bake for 40 minutes.", 40)
        ])
        #expect(found == [
            Step(index: 1, phase: .bulk, minutes: 90),
            Step(index: 3, phase: .final, minutes: 60)
        ])
    }

    @Test("Without a shaping step the last of several rests is the final proof; a single rest is the bulk")
    func withoutShapingStep() {
        let two = steps([
            ("Teig kneten.", 10),
            ("2 Stunden gehen lassen.", 120),
            ("Nochmals 45 Minuten gehen lassen.", 45),
            ("Backen.", 40)
        ])
        #expect(two.map(\.phase) == [.bulk, .final])

        let one = steps([
            ("Teig kneten.", 10),
            ("2 Stunden gehen lassen.", 120),
            ("Backen.", 40)
        ])
        #expect(one == [Step(index: 1, phase: .bulk, minutes: 120)])
    }

    @Test("The fridge, soakers, the autolyse and short pauses do not count")
    func excludedSteps() {
        let found = steps([
            ("Brühstück: Altbrot mit kochendem Wasser übergießen und 2 Stunden quellen lassen.", 120),
            ("Autolyse 45 Minuten.", 45),
            ("Mehl und Wasser mischen und 30 Minuten ruhen lassen.", 30),
            ("Dehnen und falten.", 5),
            ("Dehnen und falten (nach 30 Minuten).", 30),
            ("Add the rest of the flour and knead for 15 minutes.", 15),
            ("Restliche Zutaten zugeben und 20 Minuten kneten.", 20),
            ("Teig formen.", 0),
            ("Über Nacht im Kühlschrank reifen lassen.", 720),
            ("Retard in the fridge overnight.", 600),
            ("Backen.", 45)
        ])
        #expect(found == [
            Step(index: 2, phase: .bulk, minutes: 30),
            Step(index: 4, phase: .bulk, minutes: 30)
        ])
    }

    @Test("A preferment named in the main dough's step is no preferment ripening")
    func prefermentGoesIntoTheDough() {
        let found = steps([
            ("Sauerteig: 50 g Anstellgut mit Mehl und Wasser verrühren, 10 Stunden reifen lassen.", 600),
            ("Alle Zutaten mit dem Sauerteig verkneten und 3 Stunden ruhen lassen.", 180),
            ("Hauptteig: Sauerteig, Mehl, Wasser und Salz mischen, 2 Stunden gehen lassen.", 120),
            ("Formen.", 0),
            ("60 Minuten gehen lassen.", 60),
            ("Backen.", 45)
        ])
        #expect(found.map(\.phase) == [.preferment, .bulk, .bulk, .final])
    }

    @Test("French wording: pointage, apprêt and a stated temperature")
    func frenchRecipe() {
        let found = steps([
            ("Pétrir 10 minutes.", 10),
            ("Pointage : 2 h à 25 °C.", 120),
            ("Façonner.", 0),
            ("Apprêt : 1 h 30.", 90),
            ("Cuire 40 min.", 40)
        ])
        #expect(found == [
            Step(index: 1, phase: .bulk, minutes: 120, statedTemperature: 25),
            Step(index: 3, phase: .final, minutes: 90)
        ])
    }

    @Test("The temperature a step names, in °C; the oven's does not count")
    func statedTemperature() {
        #expect(ProofTiming.statedTemperature(in: "2 Stunden bei 26 °C gehen lassen") == 26)
        #expect(ProofTiming.statedTemperature(in: "bei 24–26 °C reifen lassen") == 25)
        #expect(ProofTiming.statedTemperature(in: "bei 26 Grad ruhen lassen") == 26)
        #expect(ProofTiming.statedTemperature(in: "bei 26° gehen lassen") == 26)
        #expect(ProofTiming.statedTemperature(in: "Proof at 78 °F for an hour") == 25.6)
        #expect(ProofTiming.statedTemperature(in: "Pointage à 25,5 °C") == 25.5)
        #expect(ProofTiming.statedTemperature(in: "45 Minuten bei 250 °C backen") == nil)
        #expect(ProofTiming.statedTemperature(in: "bei Raumtemperatur gehen lassen") == nil)
        #expect(ProofTiming.statedTemperature(in: "12 Stunden reifen lassen") == nil)
    }

    // MARK: Today's durations from the recipe

    @Test("Without bakes the recipe's duration is scaled by 2.5 per 10 °C from its reference")
    func scaledFromRecipe() throws {
        let bulk = [Step(index: 1, phase: .bulk, minutes: 123)]

        let same = try #require(ProofTiming.adjustments(steps: bulk, history: [], at: 22).first)
        #expect(same.minutes == 123 && !same.differs && same.source == .recipe)
        #expect(same.referenceTemperature == 22)

        #expect(ProofTiming.adjustments(steps: bulk, history: [], at: 12).first?.minutes == 310)
        #expect(ProofTiming.adjustments(steps: bulk, history: [], at: 32).first?.minutes == 50)

        // A step written for 26 °C takes longer in a 22 °C kitchen.
        let warm = [Step(index: 1, phase: .bulk, minutes: 120, statedTemperature: 26)]
        let cooler = try #require(ProofTiming.adjustments(steps: warm, history: [], at: 22).first)
        #expect(cooler.minutes == 175)
        #expect(cooler.referenceTemperature == 26)
        #expect(cooler.minutesByIndex == [1: 175])
    }

    @Test("Every phase gets its own adjustment, in order")
    func phasesInOrder() {
        let all = [Step(index: 0, phase: .preferment, minutes: 600),
                   Step(index: 2, phase: .bulk, minutes: 180),
                   Step(index: 4, phase: .final, minutes: 60)]
        let adjustments = ProofTiming.adjustments(steps: all, history: [], at: 18)
        #expect(adjustments.map(\.phase) == [.preferment, .bulk, .final])
        #expect(adjustments.map(\.minutes) == [865, 260, 85])
    }

    // MARK: Today's durations from the bakes

    @Test("A measured proof is brought to today's temperature; an unmeasured phase falls back to the recipe")
    func estimatedFromBakes() throws {
        let recipe = [Step(index: 1, phase: .bulk, minutes: 60),
                      Step(index: 3, phase: .final, minutes: 45)]
        let history = [BakeHistoryFacts(roomTemperature: 21, bulkProofMinutes: 95)]

        let adjustments = ProofTiming.adjustments(steps: recipe, history: history, at: 24)
        let bulk = try #require(adjustments.first { $0.phase == .bulk })
        // 95 min at 21 °C is ≈87 at 22 °C and ≈72 at 24 °C.
        #expect(bulk.minutes == 70)
        #expect(bulk.plannedMinutes == 60)
        #expect(bulk.source == .bakes(1))

        let final = try #require(adjustments.first { $0.phase == .final })
        #expect(final.source == .recipe)
        // 45 min at 22 °C, two degrees warmer: 45 / 2.5^0.2 ≈ 37 min.
        #expect(final.minutes == 35)
    }

    @Test("A phase of several steps shares the estimate in proportion")
    func sharedAmongSteps() throws {
        let recipe = [Step(index: 1, phase: .bulk, minutes: 30),
                      Step(index: 2, phase: .bulk, minutes: 60)]
        let history = [BakeHistoryFacts(roomTemperature: 22, bulkProofMinutes: 120)]
        let bulk = try #require(ProofTiming.adjustments(steps: recipe, history: history, at: 22).first)
        #expect(bulk.minutesByIndex == [1: 40, 2: 80])
        #expect(bulk.minutes == 120)
    }

    @Test("A bake without a room temperature counts as one at the reference temperature")
    func bakeWithoutTemperature() {
        let observations = ProofTiming.observations(of: .final,
                                                    in: [BakeHistoryFacts(finalProofMinutes: 50),
                                                         BakeHistoryFacts(roomTemperature: 20, bulkProofMinutes: 90)])
        #expect(observations == [StarterRipeness.Observation(temperature: 22, peakMinutes: 50)])
        #expect(ProofTiming.observations(of: .preferment, in: [BakeHistoryFacts(bulkProofMinutes: 90)]).isEmpty)
    }

    // MARK: The recipe's durations from the bakes

    @Test("The bakes say what the recipe's duration should be at its reference temperature")
    func recipeDurationsFromBakes() throws {
        let recipe = [Step(index: 1, phase: .bulk, minutes: 60),
                      Step(index: 3, phase: .final, minutes: 45)]
        // Cold kitchen, slow proof: at 22 °C the bulk would have taken ≈66 min.
        let history = [BakeHistoryFacts(roomTemperature: 18, bulkProofMinutes: 95)]

        let durations = ProofTiming.recipeDurations(steps: recipe, history: history)
        let bulk = try #require(durations.first)
        #expect(durations.count == 1)
        #expect(bulk.phase == .bulk && bulk.bakes == 1)
        #expect(bulk.minutes == 65 && bulk.plannedMinutes == 60 && bulk.differs)
        #expect(bulk.minutesByIndex == [1: 65])

        #expect(ProofTiming.recipeDurations(steps: recipe, history: []).isEmpty)
    }

    @Test("A step with its own temperature is brought to that temperature")
    func recipeDurationsAtStatedTemperature() throws {
        let recipe = [Step(index: 1, phase: .bulk, minutes: 120, statedTemperature: 26)]
        let history = [BakeHistoryFacts(roomTemperature: 26, bulkProofMinutes: 150)]
        let bulk = try #require(ProofTiming.recipeDurations(steps: recipe, history: history).first)
        #expect(bulk.referenceTemperature == 26)
        #expect(bulk.minutes == 150)
    }
}
