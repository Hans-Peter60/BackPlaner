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

    @Test("Folds as sub-steps of the bulk proof are not counted again, and the last of them is no final proof")
    func subStepsOfTheBulkProof() {
        // Hans-Peter's Sonntags-Dinkelbrötchen: the folds 3.1 and 3.2 run
        // during step 3 with the rest of its time as their duration. Read
        // as rests of their own, the bulk proof came out as 19½ hours and
        // the last fold as a 9-hour final proof.
        let instructions = [
            "Die Kochstückzutaten unter Rühren aufkochen, bis sie abbinden. Auskühlen lassen.",
            "Hauptteig: Alle Zutaten 8 Minuten auf niedrigster Stufe kneten (Teigtemperatur ca. 22°C).",
            "Den Teig 8-12 Stunden bei 20°C lagern und in den ersten 30 und 60 Minuten dehnen und falten.",
            "Teig dehnen und falten (nach 30 Minuten).",
            "Teig dehnen und falten (nach 60 Minuten).",
            "Den Teig auf die Arbeitsfläche geben und 9 eckige Teiglinge abstechen.",
            "Auf Backpapier setzen und bei Raumtemperatur 20 Minuten gehen lassen.",
            "Bei 250 °C 20 Minuten backen."
        ]
        let durations = [120, 15, 600, 570, 540, 10, 20, 20]
        let numbers: [Double] = [1, 2, 3, 3.1, 3.2, 4, 5, 6]
        let found = ProofTiming.steps(instructions: instructions, durations: durations, stepNumbers: numbers)
        #expect(found.map(\.index) == [2, 6])
        #expect(found.map(\.phase) == [.bulk, .final])
        #expect(found.map(\.minutes) == [600, 20])
        #expect(found[0].statedTemperature == 20)

        // Without the numbers the folds still count, as before.
        let unnumbered = ProofTiming.steps(instructions: instructions, durations: durations)
        #expect(unnumbered.count == 4)
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

    @Test("A baguette from a public recipe: the autolyse's rest is no bulk, \"anspringen lassen\" is")
    func autolyseRestAndWarmStart() {
        let found = steps([
            ("Autolyse: Mehl und Wasser mischen.", 0),
            ("30 Minuten ruhen lassen zur Verbesserung von Struktur und Geschmack.", 30),
            ("Hauptteig: Sauerteig und Salz (sowie optional Hefe) einarbeiten.", 0),
            ("3–5 Minuten kneten (von Hand oder mit der Maschine).", 5),
            ("30 Minuten bei Raumtemperatur anspringen lassen.", 30),
            ("Einmal dehnen und falten (stretch & fold).", 0),
            ("Weitere 30 Minuten bei Raumtemperatur anspringen lassen (insgesamt 1 Stunde Anspringzeit).", 30),
            ("10–14 Stunden zur Übernachtgare in den Kühlschrank (4–6°C) stellen.", 720),
            ("Mit der Teigkarte 3 Stücke abstechen. Nicht kneten, nicht formen, nur sanft langziehen.", 0),
            ("Baguetteteiglinge 20–30 Minuten bei Raumtemperatur zur Stückgare ruhen lassen.", 25),
            ("Mit Dampf 15 Minuten bei 250°C backen.", 15)
        ])
        #expect(found == [
            Step(index: 4, phase: .bulk, minutes: 30),
            Step(index: 6, phase: .bulk, minutes: 30),
            Step(index: 9, phase: .final, minutes: 25)
        ])
    }

    @Test("The baguette's English and French translations: autolysis, \"let it sit\" and the glossary's warm start",
          arguments: [
            ["Autolysis: Mix flour and water.", "Let rest for 30 minutes to improve structure and flavor.",
             "Knead for 3–5 minutes (by hand or with a machine).", "Let it sit for 30 minutes at room temperature.",
             "Once stretch and fold (stretch & fold).",
             "Let the fermentation start for another 30 minutes at room temperature.",
             "10–14 hours to store overnight in the refrigerator (4–6°C).",
             "Cut 3 pieces with the pastry cutter. Do not knead, do not shape, only gently stretch.",
             "Let the baguette dough rise at room temperature for 20–30 minutes to final proof.",
             "Bake with steam for 15 minutes at 250°C."],
            ["Autolyse : Mélanger la farine et l'eau.", "Laisser reposer pendant 30 minutes pour améliorer la structure et le goût.",
             "Pétrir pendant 3 à 5 minutes (à la main ou avec la machine).",
             "Laisser démarrer la fermentation pendant 30 minutes à température ambiante.",
             "Étirer et plier une fois (stretch & fold).",
             "Laisser démarrer la fermentation pendant encore 30 minutes à température ambiante.",
             "10 à 14 heures pour mettre au réfrigérateur (4 à 6°C) pour la conservation.",
             "Avec la carte de pâte, découpez 3 pièces. Ne pétrissez pas, ne façonnez pas, étirez simplement doucement.",
             "Laisser reposer les pâtes à baguettes 20 à 30 minutes à température ambiante pour apprêt.",
             "Cuire au vapeur pendant 15 minutes à 250°C."]
          ])
    func translatedBaguette(_ texts: [String]) {
        let found = ProofTiming.steps(instructions: texts, durations: [0, 30, 5, 30, 0, 30, 720, 0, 25, 15])
        #expect(found == [
            Step(index: 3, phase: .bulk, minutes: 30),
            Step(index: 5, phase: .bulk, minutes: 30),
            Step(index: 8, phase: .final, minutes: 25)
        ])
    }

    @Test("A sourdough bread's translations: \"let it ripen\" and \"laisser mûrir\" are rests",
          arguments: [
            ["Sourdough: mix all components", "Sourdough let it ripen at 30 degrees",
             "Main dough: add all components in the order given and mix into a firm dough",
             "Allow to ripen for 3 hours at 30 degrees.", "Stretching and folding", "Stretching and folding",
             "Shape into a round loaf", "Let it ripen in the floured banneton",
             "At 250 degrees, bake at 220 degrees with steam"],
            ["Levain: mélanger tous les composants", "Levain laisser mûrir à 30 degrés",
             "Pâte principale: ajouter tous les composants dans l'ordre indiqué et mélanger pour obtenir une pâte homogène",
             "Laisser reposer pendant 3 heures à 30 degrés.", "Étirer et plier", "Étirer et plier",
             "Former une boule ronde", "Laisser reposer dans le banneton tamisé",
             "À 250 degrés, cuire au vapeur à 220 degrés."]
          ])
    func translatedSourdough(_ texts: [String]) {
        let found = ProofTiming.steps(instructions: texts, durations: [10, 180, 12, 180, 150, 120, 5, 120, 50])
        #expect(found == [
            Step(index: 1, phase: .preferment, minutes: 180, statedTemperature: 30),
            Step(index: 3, phase: .bulk, minutes: 180, statedTemperature: 30),
            Step(index: 4, phase: .bulk, minutes: 150),
            Step(index: 5, phase: .bulk, minutes: 120),
            Step(index: 7, phase: .final, minutes: 120)
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
        // The dough's or the water's temperature is none to proof at.
        #expect(ProofTiming.statedTemperature(in: "Kneten, bis der Teig glatt und geschmeidig aussieht (gewünschte Teigtemperatur: ca. 28 °C) und reifen lassen.") == nil)
        #expect(ProofTiming.statedTemperature(in: "Mischen, TT 26 °C, 1 Stunde ruhen") == nil)
        #expect(ProofTiming.statedTemperature(in: "Mit Wasser von 30 °C mischen und gehen lassen") == nil)
        #expect(ProofTiming.statedTemperature(in: "Mix to a dough temperature of 78 °F and let rise") == nil)
        #expect(ProofTiming.statedTemperature(in: "Pétrir, température de pâte 25 °C, laisser pousser") == nil)
        #expect(ProofTiming.statedTemperature(in: "Teigtemperatur 26 °C, dann bei 28 °C gehen lassen") == 28)
        #expect(ProofTiming.statedTemperature(in: "Glatt kneten und bei 26 °C gehen lassen") == 26)
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

        // A step written for 26 °C stands at 26 °C: the room does not
        // matter. Set to 22 °C — no warm place at hand — it takes longer.
        let warm = [Step(index: 1, phase: .bulk, minutes: 120, statedTemperature: 26)]
        let atPlace = try #require(ProofTiming.adjustments(steps: warm, history: [], at: 22).first)
        #expect(atPlace.minutes == 120 && atPlace.temperature == 26 && atPlace.placeTemperature == 26)
        #expect(atPlace.defaultTemperature == 26 && !atPlace.isAssumedPlace)
        let cooler = try #require(ProofTiming.adjustments(steps: warm, history: [], at: 22,
                                                          phaseTemperatures: [.bulk: 22]).first)
        #expect(cooler.minutes == 175)
        #expect(cooler.referenceTemperature == 26 && cooler.temperature == 22)
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

    /// Kartoffelbrot mit Saaten, as Hans-Peter's recipe has it: the bulk
    /// proof is 45 + 30 + 120 minutes for 22 °C, the first step naming the
    /// dough's target temperature. At 22 °C the planned bulk proof stays as
    /// it is; it came out 3h 50m instead of 3h 15m.
    @Test("A bulk proof planned for the room's temperature stays as planned, whatever dough temperature a step names")
    func doughTemperatureIsNoProofTemperature() {
        let instructions = ["Brühstück mit der Saatenmischung herstellen", "Kartoffeln abkochen",
                            "Weizensauerteig Zutaten Mischen, bis sie sich zu einem festen Teig verbunden haben.",
                            "Zunächst das heiße Wasser mit den Kartoffeln mischen.",
                            "Dann alle weiteren Zutaten in der genannten Reihenfolge in die Schüssel wiegen.",
                            "Kneten, bis der Teig glatt und geschmeidig aussieht (gewünschte Teigtemperatur: ca. 28 °C) und reifen lassen. ",
                            "Dehnen und Falten", "Dehnen und Falten",
                            "Den Teigling straff rundwirken. Dabei etwas Roggenmehl in den Schluss einarbeiten, um ihn offenzuhalten.",
                            "2 Stunden bei 28 °C mit Schluss nach unten im leicht bemehlten Gärkorb zugedeckt reifen lassen.",
                            "Das Backpapier mit dem Teigling (Schluss nach oben) mithilfe eines flachen Bleches oder Brettes in den auf 250 °C vorgeheizten Ofen auf den Backstein befördern.",
                            "Dampf ablassen"]
        let durations = [600, 580, 150, 3, 8, 45, 30, 120, 10, 120, 50, 30]
        let steps = ProofTiming.steps(instructions: instructions, durations: durations)
        let adjustments = ProofTiming.adjustments(steps: steps, history: [], at: 22)
        let bulk = adjustments.first { $0.phase == .bulk }
        #expect(bulk?.plannedMinutes == 195)
        #expect(bulk?.minutes == 195)
        #expect(bulk?.referenceTemperature == 22)
        // The final proof stands at 28 °C as the recipe says; set to the
        // room's 22 °C it takes longer.
        let final = adjustments.first { $0.phase == .final }
        #expect(final?.plannedMinutes == 120 && final?.minutes == 120 && final?.temperature == 28)
        let cool = ProofTiming.adjustments(steps: steps, history: [], at: 22, phaseTemperatures: [.final: 22])
            .first { $0.phase == .final }
        #expect((cool?.minutes ?? 0) > 120 && cool?.referenceTemperature == 28)
    }

    // MARK: Where the recipe puts the dough

    @Test("A warm place without a number is a place, taken for 26 °C until the baker says better",
          arguments: ["Teig im ausgeschalteten Backofen mit eingeschalteter Lampe 90 Minuten gehen lassen",
                      "Abgedeckt an einem warmen Ort 90 Minuten gehen lassen",
                      "Im Gärschrank 90 Minuten gehen lassen",
                      "Let rise in a warm place for 90 minutes",
                      "Laisser lever 90 minutes dans un endroit chaud"])
    func warmPlace(_ text: String) throws {
        let steps = ProofTiming.steps(instructions: ["Teig kneten", text], durations: [10, 90])
        let step = try #require(steps.first)
        #expect(step.warmPlace && step.statedTemperature == nil && step.placeTemperature == 26)
        let adjustment = try #require(ProofTiming.adjustments(steps: steps, history: [], at: 20).first)
        #expect(adjustment.minutes == 90 && adjustment.isAssumedPlace && adjustment.temperature == 26)
        #expect(adjustment.sourceText(locale: Locale(identifier: "de_DE")).contains("angenommen"))
    }

    @Test("A step at room temperature or in the fridge is at no place")
    func noPlace() {
        let steps = ProofTiming.steps(instructions: ["Teig kneten", "60 Minuten gehen lassen", "Formen", "Stückgare 45 Minuten"],
                                      durations: [10, 60, 5, 45])
        #expect(steps.allSatisfy { !$0.warmPlace && $0.placeTemperature == nil })
        let adjustments = ProofTiming.adjustments(steps: steps, history: [], at: 18)
        #expect(adjustments.allSatisfy { $0.placeTemperature == nil && $0.temperature == 18 && $0.defaultTemperature == 18 })
        #expect(adjustments.allSatisfy { $0.minutes > $0.plannedMinutes })
    }

    @Test("In a phase at a place, a step at no place of its own still follows the room, and the other way round")
    func mixedPhase() throws {
        // Bulk: 30 min kneading rest at room temperature, then 120 min at 28 °C.
        let bulk = [Step(index: 1, phase: .bulk, minutes: 30), Step(index: 2, phase: .bulk, minutes: 120, statedTemperature: 28)]
        let placed = try #require(ProofTiming.adjustments(steps: bulk, history: [], at: 18).first)
        #expect(placed.placeTemperature == 28 && placed.temperature == 28)
        #expect(placed.minutesByIndex[2] == 120)
        #expect((placed.minutesByIndex[1] ?? 0) > 30)
        // Bulk mostly at room temperature with a short warm step: that step stays.
        let room = [Step(index: 1, phase: .bulk, minutes: 120), Step(index: 2, phase: .bulk, minutes: 30, statedTemperature: 28)]
        let atRoom = try #require(ProofTiming.adjustments(steps: room, history: [], at: 18, phaseTemperatures: [.bulk: 16]).first)
        #expect(atRoom.placeTemperature == nil && atRoom.temperature == 16)
        #expect(atRoom.minutesByIndex[2] == 30)
        #expect((atRoom.minutesByIndex[1] ?? 0) > 120)
    }

    @Test("The line under a phase says where the dough stands")
    func sourceTexts() throws {
        let german = Locale(identifier: "de_DE")
        let stated = [Step(index: 1, phase: .final, minutes: 120, statedTemperature: 28)]
        let atPlace = try #require(ProofTiming.adjustments(steps: stated, history: [], at: 22).first)
        #expect(atPlace.sourceText(locale: german).contains("wie im Rezept"))
        let moved = try #require(ProofTiming.adjustments(steps: stated, history: [], at: 22, phaseTemperatures: [.final: 22]).first)
        #expect(moved.sourceText(locale: german).contains("bezogen auf"))
    }

    @Test("Bakes that measured a phase are estimated for the phase's temperature")
    func historyAtPhaseTemperature() throws {
        let steps = [Step(index: 1, phase: .final, minutes: 120, statedTemperature: 28)]
        let history = [BakeHistoryFacts(roomTemperature: 28, finalProofMinutes: 100),
                       BakeHistoryFacts(roomTemperature: 28, finalProofMinutes: 110)]
        let adjustment = try #require(ProofTiming.adjustments(steps: steps, history: history, at: 20).first)
        #expect(adjustment.temperature == 28)
        if case .bakes = adjustment.source {} else { Issue.record("expected an estimate from the bakes") }
        #expect(adjustment.minutes < 120)
    }

    @Test("French folds count as part of the bulk proof, however the translation words them",
          arguments: ["Étirer et plier", "Étirer et replier", "Étirer et rabattre", "Pliage"])
    func frenchFolds(_ fold: String) {
        let steps = ProofTiming.steps(instructions: ["Pétrir jusqu'à ce que la pâte soit lisse et laisser reposer", fold, fold,
                                                     "Façonner en boule", "Laisser lever 2 heures à 28 °C dans le banneton"],
                                      durations: [45, 30, 120, 10, 120])
        #expect(steps.filter { $0.phase == .bulk }.map(\.minutes) == [45, 30, 120], "\(fold)")
    }
}

