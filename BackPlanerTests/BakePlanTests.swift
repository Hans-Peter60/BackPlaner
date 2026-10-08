//
//  BakePlanTests.swift
//  BackPlanerTests
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("The plan both baking views share")
struct BakePlanTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: hour, minute: minute))!
    }

    /// Knead, rise, bake at 250 °C, cool: the bake is not the last step.
    private let loaf = [
        PlanStep(instruction: "Teig kneten", step: 1, startTime: 0, duration: 10),
        PlanStep(instruction: "Teig gehen lassen", step: 2, startTime: 10, duration: 60),
        PlanStep(instruction: "Bei 250 °C backen", step: 3, startTime: 70, duration: 40),
        PlanStep(instruction: "Auskühlen lassen", step: 4, startTime: 110, duration: 30),
    ]

    private func plan(_ steps: [PlanStep], anchor: PlanAnchor = .startsAt, at date: Date? = nil,
                      language: String = "de") -> BakePlan {
        BakePlan(recipeName: "Brot", steps: steps, prepTime: 140, anchor: anchor,
                 date: date ?? time(8), languageCode: language, preheatTime: 15, calendar: calendar)
    }

    @Test("The bake is the step worded that way, not the last one")
    func findsTheBakingStep() {
        #expect(plan(loaf).bakingStep?.instruction == "Bei 250 °C backen")
    }

    @Test("A generated oven step comes before the bake and names its temperature")
    func generatesTheOvenStep() throws {
        let oven = try #require(plan(loaf).generatedOvenStep)
        #expect(oven.instruction == "Backofen anstellen (250 °C)")
        #expect(oven.startTime == 55)
        #expect(oven.step == 2.9)
        #expect(oven.duration == 15)
    }

    @Test("The oven temperature is found however the step words it",
          arguments: [
            ("Bei 250°C fallend auf 200°C 60 Minuten backen", "250 °C"),
            ("Ober-/Unterhitze 250 °C, 50 Minuten backen", "250 °C"),
            ("Mit Dampf backen (250 °C)", "250 °C"),
            ("Backen: 250 Grad fallend", "250 °C"),
            ("Von 250 °C fallend auf 210 °C backen", "250 °C"),
            ("Bake at 450°F for 30 minutes", "450 °F"),
            ("Bake at 230 for 40 minutes", "230 °C"),
            ("Cuire à 240 °C", "240 °C"),
          ])
    func readsOvenTemperatures(text: String, temperature: String) {
        #expect(BakePlan.ovenTemperature(in: text) == temperature)
    }

    @Test("Dough and proofing temperatures are no oven temperature")
    func ignoresDoughTemperatures() {
        #expect(BakePlan.ovenTemperature(in: "Bei 28 °C 2 Stunden gehen lassen") == nil)
        #expect(BakePlan.ovenTemperature(in: "Teigtemperatur 26°") == nil)
        #expect(BakePlan.ovenTemperature(in: "60 Minuten backen") == nil)
    }

    @Test("A temperature stated next to the baking step is used too")
    func findsTheTemperatureInANeighbouringStep() throws {
        let steps = [
            PlanStep(instruction: "Teig bei 28 °C gehen lassen", step: 1, startTime: 0, duration: 60),
            PlanStep(instruction: "Brot einschießen, Ofen 250 °C, kräftig schwaden", step: 2, startTime: 60, duration: 1),
            PlanStep(instruction: "50 Minuten backen", step: 3, startTime: 61, duration: 50),
        ]
        let neighbour = plan(steps)
        #expect(neighbour.bakingStep?.instruction == "50 Minuten backen")
        #expect(try #require(neighbour.generatedOvenStep).instruction == "Backofen anstellen (250 °C)")
    }

    @Test("The recipe's own \"Backofen anstellen\" gets the temperature of the bake")
    func namesTheTemperatureInTheRecipesOwnPreheatStep() {
        let steps = [
            PlanStep(instruction: "Teig formen", step: 1, startTime: 0, duration: 20),
            PlanStep(instruction: "Backofen anstellen", step: 2, startTime: 20, duration: 45),
            PlanStep(instruction: "Bei 250°C fallend auf 220°C 50-55 Minuten ohne Dampf backen", step: 3, startTime: 65, duration: 55),
        ]
        let rauris = plan(steps)
        #expect(rauris.generatedOvenStep == nil)
        #expect(rauris.ovenTemperature == "250 °C")
        #expect(rauris.scheduledSteps[1].instruction == "Backofen anstellen (250 °C)")
        #expect(rauris.allSteps.contains { $0.instruction == "Backofen anstellen (250 °C)" })
        // The recipe itself is not touched.
        #expect(rauris.steps[1].instruction == "Backofen anstellen")
    }

    @Test("Without any temperature the step keeps its plain text")
    func keepsThePlainTextWithoutTemperature() throws {
        let steps = [PlanStep(instruction: "60 Minuten backen", step: 1, startTime: 0, duration: 60)]
        #expect(try #require(plan(steps).generatedOvenStep).instruction == "Backofen anstellen")
    }

    @Test("The generated steps follow the recipe's language")
    func wordsGeneratedStepsInTheLanguage() throws {
        let english = plan(loaf, language: "en")
        #expect(try #require(english.generatedOvenStep).instruction == "Turn on the oven (250 °C)")
        #expect(english.endStep.instruction == "Baking is finished")
    }

    @Test("A recipe with its own preheating step gets no second one")
    func keepsTheRecipesOwnPreheatStep() {
        var steps = loaf
        steps.insert(PlanStep(instruction: "Backofen auf 250 °C vorheizen", step: 2.5, startTime: 40, duration: 30), at: 2)
        let withPreheat = plan(steps)

        #expect(withPreheat.generatedOvenStep == nil)
        #expect(withPreheat.preheatDuration == 0)
        #expect(withPreheat.ovenOnStep?.instruction == "Backofen auf 250 °C vorheizen")
        #expect(withPreheat.allSteps.count == steps.count + 1)
    }

    @Test("A bake in a cold oven needs no preheating time")
    func coldOvenNeedsNoPreheating() throws {
        let steps = [
            PlanStep(instruction: "Teig formen", step: 1, startTime: 0, duration: 20),
            PlanStep(instruction: "In den kalten Backofen schieben und 60 Minuten backen", step: 2, startTime: 20, duration: 60),
        ]
        let cold = plan(steps)
        #expect(cold.preheatDuration == 0)
        #expect(try #require(cold.generatedOvenStep).startTime == 20)
    }

    @Test("Starting at a time: steps fall after it, reminders count from it")
    func startsAtTheChosenTime() {
        let started = plan(loaf, anchor: .startsAt, at: time(8))
        #expect(started.baseDate == time(8))
        #expect(started.date(of: loaf[2]) == time(9, 10))
        #expect(started.reminderOffset(of: loaf[2]) == 70)
        #expect(started.date(of: started.endStep) == time(10, 20))
    }

    @Test("Finishing by a time: the plan starts prepTime earlier")
    func finishesByTheChosenTime() {
        let finished = plan(loaf, anchor: .finishesBy, at: time(18))
        #expect(finished.baseDate == time(15, 40))
        #expect(finished.date(of: finished.endStep) == time(18))
        // Reminders are set relative to the chosen time, not to the start.
        #expect(finished.reminderOffset(of: loaf[0]) == -140)
        #expect(finished.reminderOffset(of: finished.endStep) == 0)
    }

    @Test("The oven is busy from the bake until the end, cooling included")
    func bakeWindowRunsFromTheBakeToTheEnd() throws {
        let window = try #require(plan(loaf).bakeWindow)
        #expect(window.start == time(9, 10))
        #expect(window.end == time(10, 20))
    }

    @Test("The plan check sees the generated steps too")
    func plannedStepsIncludeGeneratedOnes() {
        let planned = plan(loaf).plannedSteps
        #expect(planned.count == loaf.count + 2)
        #expect(planned.contains { $0.instruction == "Backofen anstellen (250 °C)" && $0.date == time(8, 55) })
        #expect(planned.last?.step == 99)
    }

    // MARK: Falling temperature

    @Test("A falling temperature gets a turn-down step at the minute the bake names")
    func turnsTheOvenDownWhenTheStepSaysWhen() throws {
        var steps = loaf
        steps[2] = PlanStep(instruction: "Bei 250 °C einschießen, kräftig schwaden, nach 10 Minuten auf 220 °C reduzieren, 40 Minuten backen",
                            step: 3, startTime: 70, duration: 40)
        let falling = plan(steps)
        let turnDown = try #require(falling.generatedTurnDownStep)

        #expect(turnDown.instruction == "Backofen auf 220 °C zurückdrehen, Dampf ablassen")
        #expect(turnDown.startTime == 80)
        #expect(turnDown.step == 3.1)
        #expect(turnDown.duration == 0)
        // The oven itself is still switched on for the first temperature.
        #expect(falling.generatedOvenStep?.instruction == "Backofen anstellen (250 °C)")
        #expect(falling.allSteps.count == steps.count + 3)
    }

    @Test("Without a minute the heat is turned down ten minutes in, and \"ohne Dampf\" releases none")
    func turnsDownAfterTenMinutesByDefault() throws {
        var steps = loaf
        steps[2] = PlanStep(instruction: "Bei 250°C fallend auf 220°C 50-55 Minuten ohne Dampf backen", step: 3, startTime: 70, duration: 55)
        let turnDown = try #require(plan(steps).generatedTurnDownStep)

        #expect(turnDown.instruction == "Backofen auf 220 °C zurückdrehen")
        #expect(turnDown.startTime == 80)
    }

    @Test("The import's own wording of a falling bake is understood")
    func understandsTheImportersWording() throws {
        var steps = loaf
        steps[2] = PlanStep(instruction: "Bei 250 °C fallend auf 220 °C backen. Schwaden: kräftig.", step: 3, startTime: 70, duration: 45)
        #expect(try #require(plan(steps).generatedTurnDownStep).instruction == "Backofen auf 220 °C zurückdrehen, Dampf ablassen")
    }

    @Test("A convection figure given alongside is no falling temperature")
    func convectionIsNoDrop() {
        var steps = loaf
        steps[2] = PlanStep(instruction: "Ober-/Unterhitze 230 °C (Umluft 210 °C), 45 Minuten backen", step: 3, startTime: 70, duration: 45)
        #expect(plan(steps).generatedTurnDownStep == nil)
        #expect(BakePlan.temperatureDrop(in: "Bei 250 °C backen") == nil)
        #expect(BakePlan.temperatureDrop(in: "Bei 220 °C, dann auf 240 °C erhöhen") == nil)
    }

    @Test("A drop stated in the step before the bake counts from the bake")
    func dropInTheNeighbouringStep() throws {
        let steps = [
            PlanStep(instruction: "Brot einschießen, Ofen 250 °C fallend auf 210 °C, kräftig schwaden", step: 2, startTime: 60, duration: 1),
            PlanStep(instruction: "50 Minuten backen", step: 3, startTime: 61, duration: 50),
        ]
        let turnDown = try #require(plan(steps).generatedTurnDownStep)
        #expect(turnDown.instruction == "Backofen auf 210 °C zurückdrehen, Dampf ablassen")
        #expect(turnDown.startTime == 71)
    }

    @Test("The turn-down step follows the recipe's language and unit")
    func wordsTheTurnDownInTheLanguage() throws {
        var steps = loaf
        steps[2] = PlanStep(instruction: "Bake at 450°F for 15 minutes, then reduce to 400°F and bake 25 minutes more", step: 3, startTime: 70, duration: 40)
        let english = try #require(plan(steps, language: "en").generatedTurnDownStep)
        #expect(english.instruction == "Turn the oven down to 400 °F")
        #expect(english.startTime == 85)
    }

    @Test("A generated turn-down step is recognised as such, in every language, and is no bake")
    func recognisesGeneratedTurnDownSteps() {
        for text in ["Backofen auf 220 °C zurückdrehen",
                     "Backofen auf 220 °C zurückdrehen, Dampf ablassen",
                     "Turn the oven down to 400 °F",
                     "Baisser le four à 220 °C, évacuer la buée"] {
            #expect(BakePlan.isTurnDownInstruction(text), "\(text)")
            #expect(!BakePlanValidator.isBakingStartInstruction(text), "\(text)")
        }
        // A recipe's own step that happens to mention turning down is not generated.
        #expect(!BakePlan.isTurnDownInstruction("Nach 10 Minuten den Backofen auf 220 °C zurückdrehen und weiterbacken"))
        #expect(!BakePlan.isTurnDownInstruction("Bei 250 °C backen"))
    }

    @Test("A turn-down past the end of the bake is not generated")
    func noTurnDownAfterTheBake() {
        var steps = loaf
        steps[2] = PlanStep(instruction: "Bei 250 °C fallend auf 220 °C backen", step: 3, startTime: 70, duration: 8)
        #expect(plan(steps).generatedTurnDownStep == nil)
    }
}
