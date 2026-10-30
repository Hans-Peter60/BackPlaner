//
//  ScheduledStepStoreTests.swift
//  BackPlanerTests
//
//  The scheduled steps behind the planning logic: what the Core Data store
//  answers, and what planning makes of the steps a store holds.
//

import BakePlannerCore
import CoreData
import Foundation
import Testing
@testable import BackPlaner

/// Scheduled steps in memory, for testing the planning logic without Core Data.
final class InMemoryScheduledStepStore: ScheduledStepStore {
    var stored: [ScheduledStepData]

    init(_ steps: [ScheduledStepData] = []) {
        stored = steps
    }

    func steps(excludingRecipe recipeName: String) -> [ScheduledStepData] {
        stored.filter { $0.recipeName != recipeName }
    }

    func hasSteps(recipeName: String) -> Bool {
        stored.contains { $0.recipeName == recipeName }
    }

    func hasSteps(recipeName: String, onOrAfter date: Date) -> Bool {
        stored.contains { $0.recipeName == recipeName && $0.date >= date }
    }

    func add(_ steps: [ScheduledStepData]) {
        stored += steps
    }

    func removeSteps(recipeName: String) {
        stored.removeAll { $0.recipeName == recipeName }
    }
}

private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func minute(_ offset: Int) -> Date {
    base.addingTimeInterval(TimeInterval(offset * 60))
}

private func scheduled(_ recipe: String, _ step: Double, _ instruction: String, at date: Date,
                       plan: UUID? = nil) -> ScheduledStepData {
    ScheduledStepData(id: UUID(), planID: plan, recipeName: recipe, instruction: instruction,
                      step: step, startTime: 0, duration: 0, date: date,
                      isAutomaticRecurrence: false, servingScale: 1)
}

/// Knead, bake, finish — a plan whose oven phase runs from the bake to the finish.
private func bake(_ recipe: String, startingAt start: Int) -> [ScheduledStepData] {
    [
        scheduled(recipe, 1, "Teig kneten", at: minute(start)),
        scheduled(recipe, 2, "Im Ofen backen", at: minute(start + 60)),
        scheduled(recipe, 99, "Backvorgang ist beendet", at: minute(start + 120)),
    ]
}

@Suite("Planning against the scheduled steps of a store")
struct ScheduledStepPlanningTests {

    @Test("The oven phases leave out the recipe being replaced and bakes already over")
    func scheduledBakeWindows() throws {
        let store = InMemoryScheduledStepStore(
            bake("Brot", startingAt: 0) + bake("Kuchen", startingAt: 30) + bake("Torte", startingAt: -300)
        )

        let windows = BakePlanValidator.scheduledBakeWindows(excluding: "Brot", from: store, now: base)

        #expect(windows.map(\.recipeName) == ["Kuchen"])
        let window = try #require(windows.first)
        #expect(window.start == minute(90))
        #expect(window.end == minute(150))
    }

    @Test("A plan becomes one scheduled step per step, with the plan's data on each")
    func scheduledStepData() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let plan = BakePlan(recipeName: "Brot",
                            steps: [
                                PlanStep(instruction: "Teig kneten", step: 1, startTime: 0, duration: 10),
                                PlanStep(instruction: "Teig gehen lassen", step: 2, startTime: 10, duration: 60),
                                PlanStep(instruction: "Bei 250 °C backen", step: 3, startTime: 70, duration: 40),
                            ],
                            prepTime: 110, anchor: .startsAt, date: base, languageCode: "de",
                            preheatTime: 15, calendar: calendar)
        let planID = UUID()

        let data = plan.scheduledStepData(planID: planID, servingScale: 1.5, isAutomaticRecurrence: true)

        #expect(data.map(\.step) == plan.allSteps.map(\.step))
        #expect(data.map(\.instruction) == plan.allSteps.map(\.instruction))
        #expect(data.map(\.startTime) == plan.allSteps.map(\.startTime))
        #expect(data.map(\.duration) == plan.allSteps.map(\.duration))
        #expect(data.map(\.date) == plan.allSteps.map(plan.date(of:)))
        #expect(data.allSatisfy {
            $0.planID == planID && $0.recipeName == "Brot" && $0.servingScale == 1.5 && $0.isAutomaticRecurrence
        })
        #expect(Set(data.compactMap(\.id)).count == data.count)
    }

    @Test("Removing a recipe's plans leaves the other recipes' steps alone")
    func removePlansKeepsOtherRecipes() {
        let store = InMemoryScheduledStepStore(bake("Brot", startingAt: 0) + bake("Kuchen", startingAt: 30))

        BakePlanScheduler.removePlans(recipeName: "Brot", reminderPrefix: "test-store",
                                      keeping: UUID(), from: store)

        #expect(!BakePlanScheduler.hasPlan(recipeName: "Brot", from: store))
        #expect(BakePlanScheduler.hasPlan(recipeName: "Kuchen", from: store))
        #expect(store.stored.count == 3)
    }

    @Test("A plan counts as pending while a step lies at or after now")
    func pendingPlan() {
        let store = InMemoryScheduledStepStore(bake("Brot", startingAt: 0))

        #expect(BakePlanScheduler.hasPendingPlan(recipeName: "Brot", now: minute(120), from: store))
        #expect(!BakePlanScheduler.hasPendingPlan(recipeName: "Brot", now: minute(121), from: store))
        #expect(!BakePlanScheduler.hasPendingPlan(recipeName: "Kuchen", now: base, from: store))
    }
}

// On the main actor: the store works on the view context, which is a
// main-queue context.
@Suite("Scheduled steps kept in Core Data")
@MainActor
struct CoreDataScheduledStepStoreTests {

    private func makeStore() -> CoreDataScheduledStepStore {
        CoreDataScheduledStepStore(context: PersistenceController(inMemory: true).container.viewContext)
    }

    @Test("Stored steps come back with every field")
    func roundTrip() throws {
        let store = makeStore()
        var step = scheduled("Brot", 2.5, "Im Ofen backen", at: minute(60), plan: UUID())
        step.startTime = 60
        step.duration = 40
        step.isAutomaticRecurrence = true
        step.servingScale = 1.37
        store.add([step, scheduled("Kuchen", 1, "Teig rühren", at: minute(0))])

        let found = store.steps(excludingRecipe: "Kuchen")

        #expect(found == [step])
    }

    @Test("Asking for a recipe's steps, with and without a date")
    func hasSteps() {
        let store = makeStore()
        store.add([scheduled("Brot", 1, "Teig kneten", at: minute(0))])

        #expect(store.hasSteps(recipeName: "Brot"))
        #expect(!store.hasSteps(recipeName: "Kuchen"))
        #expect(store.hasSteps(recipeName: "Brot", onOrAfter: minute(0)))
        #expect(!store.hasSteps(recipeName: "Brot", onOrAfter: minute(1)))
    }

    @Test("Removing a recipe's steps leaves the others")
    func removeSteps() {
        let store = makeStore()
        store.add(bake("Brot", startingAt: 0) + bake("Kuchen", startingAt: 30))

        store.removeSteps(recipeName: "Brot")

        #expect(!store.hasSteps(recipeName: "Brot"))
        #expect(store.steps(excludingRecipe: "Brot").count == 3)
    }
}
