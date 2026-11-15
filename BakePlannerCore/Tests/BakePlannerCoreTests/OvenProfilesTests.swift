//
//  OvenProfilesTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Oven profiles")
struct OvenProfilesTests {

    private let miele = OvenProfile(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                                    name: "Miele", preheatMinutes: 20, stonePreheatMinutes: 60, runsHotBy: 10)
    private let fan = OvenProfile(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                                  name: "Umluft", preheatMinutes: 10, stonePreheatMinutes: 40,
                                  runsHotBy: 0, fanReduction: 20)

    @Test("The dial is set lower by the deviation and the fan reduction")
    func dialTemperature() {
        #expect(miele.correction(convection: false) == 10)
        #expect(miele.dialTemperature(for: 250, convection: false) == 240)
        #expect(miele.dialTemperature(for: 250, convection: true) == 220)
        #expect(fan.dialTemperature(for: 250, convection: true) == 230)
        #expect(fan.dialTemperature(for: 250, convection: false) == 250)
        let both = OvenProfile(name: "Beides", runsHotBy: -10, fanReduction: 20)
        #expect(both.dialTemperature(for: 250, convection: true) == 240)
        let exact = OvenProfile(name: "Genau")
        #expect(!exact.hasCorrection(convection: false))
        #expect(exact.hasCorrection(convection: true))
        #expect(exact.dialTemperature(for: 250, convection: false) == 250)
        #expect(OvenProfile(name: "Heiß", runsHotBy: 30).dialTemperature(for: 60, convection: false) == 50)
    }

    @Test("The dial note speaks the plan's language and stays away when the dial matches")
    func dialNote() {
        #expect(miele.dialNote(for: 250, languageCode: "de", convection: false) == "am Regler 240 °C")
        #expect(miele.dialNote(for: 250, languageCode: "en_GB", convection: false) == "dial at 240 °C")
        #expect(fan.dialNote(for: 230, languageCode: "fr", convection: true) == "thermostat sur 210 °C")
        #expect(OvenProfile(name: "Genau").dialNote(for: 250, languageCode: "de", convection: false) == nil)
    }

    @Test("The bake mode's note reads the step's temperature and skips a step that carries it already")
    func dialNoteForInstruction() {
        #expect(miele.dialNote(forInstruction: "Brot bei 250 °C einschießen", languageCode: "de", convection: false) == "am Regler 240 °C")
        #expect(miele.dialNote(forInstruction: "Brot bei 250 °C einschießen", languageCode: "de", convection: true) == "am Regler 220 °C")
        #expect(miele.dialNote(forInstruction: "Backofen anstellen (250 °C, am Regler 240 °C)", languageCode: "de", convection: false) == nil)
        #expect(miele.dialNote(forInstruction: "Teig bei 28 °C gehen lassen", languageCode: "de", convection: false) == nil)
        #expect(miele.dialNote(forInstruction: "Bake at 450 °F", languageCode: "en", convection: false) == nil)
    }

    @Test("Profiles survive the round trip through the settings string")
    func codec() {
        let json = OvenProfiles.encode([miele, fan])
        #expect(OvenProfiles.decode(json) == [miele, fan])
        #expect(OvenProfiles.decode(nil).isEmpty)
        #expect(OvenProfiles.decode("kaputt").isEmpty)
        #expect(OvenProfiles.decode("[]").isEmpty)
    }

    @Test("The chosen oven is used, the first one without a valid choice")
    func selection() {
        #expect(OvenProfiles.selected(from: [miele, fan], selectedID: fan.id.uuidString) == fan)
        #expect(OvenProfiles.selected(from: [miele, fan], selectedID: nil) == miele)
        #expect(OvenProfiles.selected(from: [miele, fan], selectedID: "gelöscht") == miele)
        #expect(OvenProfiles.selected(from: [], selectedID: nil) == nil)
    }

    @Test("The plan's oven steps name the dial setting of the chosen oven")
    func planTexts() {
        let steps = [
            PlanStep(instruction: "Teig kneten", step: 1, startTime: 0, duration: 15),
            PlanStep(instruction: "Bei 250 °C backen, nach 10 Minuten auf 220 °C zurückdrehen", step: 2, startTime: 15, duration: 45),
        ]
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = BakePlan(recipeName: "Test", steps: steps, prepTime: 60, anchor: .startsAt, date: date,
                            languageCode: "de", preheatTime: 15, stonePreheatTime: 45, ovenProfile: miele)
        #expect(plan.generatedOvenStep?.instruction == "Backofen anstellen (250 °C, am Regler 240 °C)")
        #expect(plan.generatedTurnDownStep?.instruction == "Backofen auf 220 °C zurückdrehen (am Regler 210 °C)")
        // The dial note is no second temperature for the plan check.
        #expect(BakePlan.ovenTemperatureCelsius(in: plan.generatedOvenStep?.instruction ?? "") == 250)

        let plain = BakePlan(recipeName: "Test", steps: steps, prepTime: 60, anchor: .startsAt, date: date,
                             languageCode: "de", preheatTime: 15, stonePreheatTime: 45, ovenProfile: nil)
        #expect(plain.generatedOvenStep?.instruction == "Backofen anstellen (250 °C)")
        #expect(plain.generatedTurnDownStep?.instruction == "Backofen auf 220 °C zurückdrehen")

        let exact = BakePlan(recipeName: "Test", steps: steps, prepTime: 60, anchor: .startsAt, date: date,
                             languageCode: "en", preheatTime: 15, stonePreheatTime: 45,
                             ovenProfile: OvenProfile(name: "Genau"))
        #expect(exact.generatedOvenStep?.instruction == "Turn on the oven (250 °C)")

        // The fan is a choice of the bake: the same oven, 20 °C lower.
        let fanned = plan.using(miele, convection: true)
        #expect(fanned.generatedOvenStep?.instruction == "Backofen anstellen (250 °C, am Regler 220 °C)")
        #expect(fanned.usesConvection && !plan.usesConvection)
    }
}
