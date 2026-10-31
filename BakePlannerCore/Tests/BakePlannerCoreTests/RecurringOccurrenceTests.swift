//
//  RecurringOccurrenceTests.swift
//  BakePlannerCoreTests
//
//  Which recipe on a rhythm the automatic pass plans now, and how.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("The automatic pass: which recipe on a rhythm is due")
struct RecurringOccurrenceTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// A rye starter refreshed every `interval` days: mixed, then ripening
    /// twelve hours. No oven.
    private func starter(interval: Int = 2) -> RecipeExportData {
        RecipeExportData(
            name: "Roggensauer", summary: "", prepTime: 725, totalWeight: 220, tags: [], rating: 0,
            recurrenceIntervalDays: interval,
            components: [RecipeExportComponent(name: "Roggensauer", number: 1, ingredients: [
                RecipeExportIngredient(name: "Anstellgut", number: 1, unit: "g", weight: 20, normWeight: 20, num: 0, denom: 0),
                RecipeExportIngredient(name: "Roggenmehl 1150", number: 2, unit: "g", weight: 100, normWeight: 100, num: 0, denom: 0),
                RecipeExportIngredient(name: "Wasser", number: 3, unit: "g", weight: 100, normWeight: 100, num: 0, denom: 0),
            ])],
            instructions: [
                RecipeExportInstruction(instruction: "Zutaten mischen", step: 1, duration: 5, startTime: 0, bakeFlag: false),
                RecipeExportInstruction(instruction: "Bei 26 °C 12 Stunden reifen lassen", step: 2, duration: 720,
                                        startTime: 5, bakeFlag: false),
            ])
    }

    private func bread(interval: Int = 7) -> RecipeExportData {
        var bread = RecipeStoreContract.bread()
        bread.recurrenceIntervalDays = interval
        return bread
    }

    @Test("A starter is due on its rhythm, counted from the start of its last feeding")
    func starterFromFeeding() throws {
        let store = InMemoryScheduledStepStore()
        let recipe = RecurringBakePlanner.RhythmRecipe(content: starter(), lastBakeFinish: nil,
                                                       lastFeedingStart: date(2, 8))
        let plan = try #require(RecurringBakePlanner.dueOccurrence(of: recipe, steps: store, now: date(3, 12),
                                                                   languageCode: "de", calendar: calendar))
        #expect(plan.anchor == .startsAt)
        #expect(plan.date == date(4, 8))
        #expect(plan.isStarterFeeding)
        #expect(plan.endStep.instruction == "Fütterung abgeschlossen – Ergebnis im Anstellgut-Tagebuch eintragen")
    }

    @Test("A bread is due on its rhythm, counted from its last bake")
    func breadFromBake() throws {
        let bread = bread()
        let duration = RecurringBakePlanner.planDuration(of: bread)
        let lastFinish = calendar.date(byAdding: .minute, value: duration, to: date(1, 6))!
        let recipe = RecurringBakePlanner.RhythmRecipe(content: bread, lastBakeFinish: lastFinish,
                                                       lastFeedingStart: date(5, 8))
        let plan = try #require(RecurringBakePlanner.dueOccurrence(of: recipe, steps: InMemoryScheduledStepStore(),
                                                                   now: date(3, 12), languageCode: "de",
                                                                   calendar: calendar))
        // A bread ignores feedings: a week after the last bake's start.
        #expect(plan.date == date(8, 6))
        #expect(!plan.isStarterFeeding)
    }

    @Test("Nothing is due without a rhythm, without steps, without anything to measure from, or with a plan pending")
    func notDue() {
        let store = InMemoryScheduledStepStore()
        let now = date(3, 12)
        func due(_ content: RecipeExportData, feeding: Date? = date(2, 8)) -> Bool {
            RecurringBakePlanner.dueOccurrence(of: .init(content: content, lastBakeFinish: nil, lastFeedingStart: feeding),
                                               steps: store, now: now, languageCode: "de", calendar: calendar) != nil
        }
        #expect(!due(starter(interval: 0)))
        var empty = starter()
        empty.instructions = []
        #expect(!due(empty))
        #expect(!due(starter(), feeding: nil))
        #expect(due(starter()))

        store.add([ScheduledStepData(id: UUID(), planID: UUID(), recipeName: "Roggensauer", instruction: "Zutaten mischen",
                                     step: 1, startTime: 0, duration: 5, date: date(3, 18),
                                     isAutomaticRecurrence: true, servingScale: 1)])
        #expect(!due(starter()))
        // A step of the recipe that is over no longer holds it back.
        store.removeSteps(recipeName: "Roggensauer")
        store.add([ScheduledStepData(id: UUID(), planID: UUID(), recipeName: "Roggensauer", instruction: "Zutaten mischen",
                                     step: 1, startTime: 0, duration: 5, date: date(3, 11),
                                     isAutomaticRecurrence: true, servingScale: 1)])
        #expect(due(starter()))
    }
}
