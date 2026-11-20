//
//  CloudDishImportTests.swift
//  BakePlannerCoreTests
//
//  The cloud's answer for a dish, read into a KitchenDish.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Cloud dish import")
struct CloudDishImportTests {

    private let answer = """
    {"dish": {"title": "Perlhuhn-Geschnetzeltes", "servings": 2, "sourceLanguage": "de",
      "components": ["Geschnetzeltes", "Knusprige Haut", "Birne"],
      "steps": [
        {"text": "Haut lösen, Fleisch in Streifen schneiden", "componentName": "Geschnetzeltes",
         "handsMinutes": 6, "unattendedMinutes": 0, "unattendedMinMinutes": 0, "unattendedMaxMinutes": 0,
         "station": "none", "ovenTemperature": 0, "maxWaitMinutes": -1, "dependsOn": []},
        {"text": "Haut im Ofen backen", "componentName": "Knusprige Haut",
         "handsMinutes": 2, "unattendedMinutes": 20, "unattendedMinMinutes": 20, "unattendedMaxMinutes": 25,
         "station": "oven", "ovenTemperature": 160, "maxWaitMinutes": -1, "dependsOn": [0]},
        {"text": "Fleisch scharf anbraten", "componentName": "Geschnetzeltes",
         "handsMinutes": 2, "unattendedMinutes": 0, "unattendedMinMinutes": 0, "unattendedMaxMinutes": 0,
         "station": "burner", "ovenTemperature": 0, "maxWaitMinutes": 1, "dependsOn": [5, 2]},
        {"text": "   ", "componentName": "Birne", "handsMinutes": 1, "unattendedMinutes": 0,
         "unattendedMinMinutes": 0, "unattendedMaxMinutes": 0, "station": "none", "ovenTemperature": 0,
         "maxWaitMinutes": -1, "dependsOn": []},
        {"text": "Birne karamellisieren", "componentName": "Birne",
         "handsMinutes": 5, "unattendedMinutes": 0, "unattendedMinMinutes": 0, "unattendedMaxMinutes": 0,
         "station": "burner", "ovenTemperature": 999999, "maxWaitMinutes": 10, "dependsOn": []},
        {"text": "Anrichten", "componentName": "", "handsMinutes": 3, "unattendedMinutes": 0,
         "unattendedMinMinutes": 0, "unattendedMaxMinutes": 0, "station": "none", "ovenTemperature": 0,
         "maxWaitMinutes": 0, "dependsOn": []}
      ],
      "warnings": ["Die Garzeit der Birne fehlt im Rezept."]},
     "model": "gemini-3.8-flash", "freeImports": {"used": 1, "limit": 5}}
    """

    @Test("The answer decodes, with the allowance")
    func decodes() throws {
        let analysis = try JSONDecoder().decode(CloudDishAnalysis.self, from: Data(answer.utf8))
        #expect(analysis.dish.steps.count == 6)
        #expect(analysis.freeImports?.remaining == 4)
        #expect(analysis.dish.warnings == ["Die Garzeit der Birne fehlt im Rezept."])
    }

    @Test("The dish: plausible numbers, stations, windows, waits; a blank step and forward dependencies dropped; defaults filled")
    func dish() throws {
        let analysis = try JSONDecoder().decode(CloudDishAnalysis.self, from: Data(answer.utf8))
        let dish = CloudDishImport.dish(from: analysis.dish, source: .text, now: Date(timeIntervalSince1970: 1_793_520_000))
        #expect(dish.name == "Perlhuhn-Geschnetzeltes" && dish.servings == 2 && dish.source == .text)
        #expect(dish.tasks.count == 5)
        #expect(dish.tasks.map(\.id) == ["step-1", "step-2", "step-3", "step-4", "step-5"])

        let skin = dish.tasks[1]
        #expect(skin.station == .oven && skin.ovenTemperature == 160 && skin.unattendedWindow == 20...25)
        #expect(skin.maxWait == nil && skin.after == ["step-1"])

        let sear = dish.tasks[2]
        #expect(sear.station == .burner && sear.maxWait == 1)
        // Index 5 lies ahead, index 2 is the step itself: neither counts;
        // left empty, the step follows its component's previous step.
        #expect(sear.after == ["step-1"])

        let pear = dish.tasks[3]
        #expect(pear.station == .burner && pear.ovenTemperature == nil && pear.maxWait == 10)
        #expect(pear.after.isEmpty)

        let plating = dish.tasks[4]
        #expect(plating.maxWait == 0)
        #expect(plating.after == ["step-3", "step-2", "step-4"])
        // The plan works out.
        #expect(throws: Never.self) { try KitchenScheduler.schedule(dish.tasks, budget: 35) }
    }

    @Test("No title, no steps, odd values: still a dish")
    func sparse() {
        let dish = CloudDishImport.dish(from: CloudDish(servings: -3, steps: [
            CloudDishStep(text: "Kochen", handsMinutes: -5, unattendedMinutes: 99_999_999, station: "microwave",
                          maxWaitMinutes: -1, dependsOn: [7])
        ]), source: .photo)
        #expect(!dish.name.isEmpty && dish.servings == nil)
        let step = dish.tasks[0]
        #expect(step.handsMinutes == 0 && step.unattendedMinutes == Plausible.maxMinutes)
        #expect(step.station == nil && step.after.isEmpty && step.maxWait == nil)
        let empty = CloudDishImport.dish(from: CloudDish(steps: []), source: .text)
        #expect(empty.tasks.isEmpty)
    }
}
