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
}
