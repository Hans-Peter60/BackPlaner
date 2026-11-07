//
//  OvenSettingsTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("A step's oven settings as fields")
struct OvenSettingsTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func time(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: hour))!
    }

    private func plan(_ steps: [PlanStep]) -> BakePlan {
        BakePlan(recipeName: "Brot", steps: steps, prepTime: 140, anchor: .startsAt,
                 date: time(8), languageCode: "de", preheatTime: 15, calendar: calendar)
    }

    @Test("Empty settings are nil in every model; set ones come back as one value")
    func emptyIsNil() {
        #expect(OvenSettings.from(temperature: nil, fallingTo: nil, steam: nil) == nil)
        #expect(OvenSettings.from(temperature: nil, fallingTo: nil, steam: false) == OvenSettings(steam: false))

        var instruction = RecipeExportInstruction(instruction: "Backen", step: 3, duration: 45, startTime: 70, bakeFlag: true)
        #expect(instruction.oven == nil)
        instruction.oven = OvenSettings(temperature: 250, fallingTo: 220, steam: true)
        #expect(instruction.ovenTemperature == 250 && instruction.ovenFallingTemperature == 220 && instruction.ovenSteam == true)
        instruction.oven = nil
        #expect(instruction.ovenTemperature == nil && instruction.ovenFallingTemperature == nil && instruction.ovenSteam == nil)

        let instructionFB = InstructionFB()
        instructionFB.oven = OvenSettings(temperature: 230)
        #expect(instructionFB.ovenTemperature == 230 && instructionFB.ovenSteam == nil)
    }

    @Test("The summary names what is set, in the app's words")
    func summary() {
        // The package's texts are German keys; the apps translate them.
        #expect(OvenSettings(temperature: 250, fallingTo: 220, steam: true).summary()
                == "250 °C, fallend auf 220 °C, mit Schwaden")
        #expect(OvenSettings(temperature: 180).summary() == "180 °C")
        #expect(OvenSettings(steam: false).summary() == "ohne Schwaden")
        #expect(OvenSettings().summary() == nil)
    }

    @Test("The generated oven step takes the stored temperature before the wording")
    func storedTemperatureWins() throws {
        let steps = [
            PlanStep(instruction: "Teig kneten", step: 1, startTime: 0, duration: 10),
            PlanStep(instruction: "Heiß backen", step: 2, startTime: 10, duration: 45, oven: OvenSettings(temperature: 240)),
        ]
        let plan = plan(steps)
        #expect(plan.ovenTemperature == "240 °C")
        #expect(plan.ovenTemperatureCelsius == 240)
        #expect(try #require(plan.generatedOvenStep).instruction == "Backofen anstellen (240 °C)")
        #expect(plan.bakeWindow?.temperature == 240)

        // The wording still serves a step without fields, in Celsius only.
        let worded = self.plan([PlanStep(instruction: "Bei 250 °C 45 Minuten backen", step: 1, startTime: 0, duration: 45)])
        #expect(worded.ovenTemperatureCelsius == 250)
        let fahrenheit = self.plan([PlanStep(instruction: "Bake at 450 °F for 45 minutes", step: 1, startTime: 0, duration: 45)])
        #expect(fahrenheit.ovenTemperature == "450 °F")
        #expect(fahrenheit.ovenTemperatureCelsius == nil)
    }

    @Test("A stored falling temperature generates the turn-down step, timed by the wording when it says")
    func storedDrop() throws {
        let silent = plan([
            PlanStep(instruction: "Brot backen", step: 1, startTime: 0, duration: 50,
                     oven: OvenSettings(temperature: 250, fallingTo: 220, steam: true)),
        ])
        let turnDown = try #require(silent.generatedTurnDownStep)
        #expect(turnDown.instruction == "Backofen auf 220 °C zurückdrehen, Dampf ablassen")
        #expect(turnDown.startTime == BakePlan.defaultTurnDownMinutes)

        let timed = plan([
            PlanStep(instruction: "Brot backen, nach 15 Minuten die Hitze reduzieren", step: 1, startTime: 0, duration: 50,
                     oven: OvenSettings(temperature: 250, fallingTo: 210, steam: false)),
        ])
        let timedTurnDown = try #require(timed.generatedTurnDownStep)
        #expect(timedTurnDown.instruction == "Backofen auf 210 °C zurückdrehen")
        #expect(timedTurnDown.startTime == 15)

        // Stored "no steam" overrules the wording's steam; stored steam adds it.
        let wordedSteam = plan([
            PlanStep(instruction: "Bei 250 °C fallend auf 220 °C mit Dampf backen", step: 1, startTime: 0, duration: 50,
                     oven: OvenSettings(steam: false)),
        ])
        #expect(try #require(wordedSteam.generatedTurnDownStep).instruction == "Backofen auf 220 °C zurückdrehen")
        let addedSteam = plan([
            PlanStep(instruction: "Bei 250 °C fallend auf 220 °C backen", step: 1, startTime: 0, duration: 50,
                     oven: OvenSettings(steam: true)),
        ])
        #expect(try #require(addedSteam.generatedTurnDownStep).instruction == "Backofen auf 220 °C zurückdrehen, Dampf ablassen")

        // Steam alone generates nothing.
        #expect(plan([PlanStep(instruction: "Brot backen", step: 1, startTime: 0, duration: 50,
                               oven: OvenSettings(temperature: 250, steam: true))]).generatedTurnDownStep == nil)
    }

    @Test("Two bakes at the same temperature share one oven; different or unknown ones do not")
    func sameTemperatureSharesTheOven() {
        let noon = time(12)
        func window(_ name: String, from start: Int, to end: Int, at temperature: Int?) -> BakeWindow {
            BakeWindow(recipeName: name, start: noon.addingTimeInterval(TimeInterval(start * 60)),
                       end: noon.addingTimeInterval(TimeInterval(end * 60)), temperature: temperature)
        }
        let bread = window("Brot", from: 0, to: 60, at: 250)
        let same = BakePlanValidator.issues(for: [], bakeWindow: bread,
                                            existingWindows: [window("Brötchen", from: 30, to: 90, at: 250)],
                                            ovenCount: 1, bakePause: 10)
        #expect(same.map(\.severity) == [.hint])
        #expect(same[0].message.contains("250 °C") && same[0].message.contains("Brötchen"))
        #expect(BakePlanValidator.fitsOvens(bread, existingWindows: [window("Brötchen", from: 30, to: 90, at: 250)], ovenCount: 1, bakePause: 10))

        let different = BakePlanValidator.issues(for: [], bakeWindow: bread,
                                                 existingWindows: [window("Kuchen", from: 30, to: 90, at: 180)],
                                                 ovenCount: 1, bakePause: 10)
        #expect(different.map(\.severity) == [.error])
        let unknown = BakePlanValidator.issues(for: [], bakeWindow: bread,
                                               existingWindows: [window("Kuchen", from: 30, to: 90, at: nil)],
                                               ovenCount: 1, bakePause: 10)
        #expect(unknown.map(\.severity) == [.error])
    }

    @Test("The wording suggests the fields for an oven step; other steps get none")
    func suggestedFromWording() {
        #expect(BakePlan.suggestedOvenSettings(in: "Bei 250 °C fallend auf 220 °C mit Schwaden 50 Minuten backen")
                == OvenSettings(temperature: 250, fallingTo: 220, steam: true))
        #expect(BakePlan.suggestedOvenSettings(in: "Bei 230 °C ohne Dampf backen")
                == OvenSettings(temperature: 230, steam: false))
        #expect(BakePlan.suggestedOvenSettings(in: "Backofen auf 250 °C vorheizen") == OvenSettings(temperature: 250))
        #expect(BakePlan.suggestedOvenSettings(in: "Preheat the oven with the baking stone") == nil)
        #expect(BakePlan.suggestedOvenSettings(in: "Bake at 450 °F for 45 minutes") == nil)
        #expect(BakePlan.suggestedOvenSettings(in: "Bei 28 °C 3 Stunden gehen lassen") == nil)
        #expect(BakePlan.suggestedOvenSettings(in: "Teig kneten") == nil)
        #expect(BakePlan.suggestedOvenSettings(in: "Dampf ablassen") == nil)
    }

    @Test("A scheduled plan's window reads the temperature from its steps' wording")
    func windowFromScheduledSteps() {
        let steps = [
            PlannedStep(instruction: "Backofen anstellen (230 °C)", step: 1.9, date: time(9)),
            PlannedStep(instruction: "Brot backen", step: 2, date: time(10)),
            PlannedStep(instruction: "Backvorgang ist beendet", step: 99, date: time(11)),
        ]
        #expect(BakePlanValidator.bakeWindow(recipeName: "Brot", steps: steps)?.temperature == 230)
    }
}
