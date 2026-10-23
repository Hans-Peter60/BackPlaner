//
//  SiriIntentTests.swift
//  BackPlanerTests
//
//  The decisions behind the Siri commands: which planned step is "the next
//  one", which step is the bake, when a feeding counts as already logged,
//  and how loosely a spoken starter name is matched.
//

import CoreData
import Foundation
import Testing
@testable import BackPlaner

// MARK: - Feeding rules

@Suite("Starter feeding rules")
struct StarterFeedingRulesTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A feeding within the last hour is the same feeding")
    func sameFeedingWithinTheHour() {
        #expect(StarterFeedingRules.isSameFeeding(lastFeeding: now.addingTimeInterval(-20 * 60), now: now))
        #expect(StarterFeedingRules.isSameFeeding(lastFeeding: now, now: now))
    }

    @Test("Older feedings, future dates and no feeding at all are not")
    func distinctFeedings() {
        #expect(!StarterFeedingRules.isSameFeeding(lastFeeding: now.addingTimeInterval(-2 * 60 * 60), now: now))
        #expect(!StarterFeedingRules.isSameFeeding(lastFeeding: now.addingTimeInterval(-StarterFeedingRules.duplicateWindow), now: now))
        #expect(!StarterFeedingRules.isSameFeeding(lastFeeding: now.addingTimeInterval(10 * 60), now: now))
        #expect(!StarterFeedingRules.isSameFeeding(lastFeeding: nil, now: now))
    }

    @Test("Spoken names match without case, accents, spaces or hyphens")
    func looseNameMatching() {
        #expect(StarterFeedingRules.nameMatches("Roggensauer", query: "roggen sauer"))
        #expect(StarterFeedingRules.nameMatches("Lievito Madre", query: "lievito-madre"))
        #expect(StarterFeedingRules.nameMatches("Weizensauer (süß)", query: "weizensauer suss"))
        #expect(StarterFeedingRules.nameMatches("Roggensauer", query: "Roggen"))
        #expect(StarterFeedingRules.nameMatches("Roggensauer", query: ""))
    }

    @Test("A different starter does not match")
    func otherStarterDoesNotMatch() {
        #expect(!StarterFeedingRules.nameMatches("Weizensauer", query: "Roggen"))
        #expect(!StarterFeedingRules.nameMatches("Roggensauer", query: "Roggensauerteig"))
    }
}

// MARK: - Feeding store

@Suite("Logging feedings for the starters")
@MainActor
struct StarterFeedingStoreTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func recipe(_ name: String, rhythmDays: Int, in context: NSManagedObjectContext) -> Recipe {
        let recipe = Recipe(context: context)
        recipe.id = UUID()
        recipe.name = name
        recipe.summary = ""
        recipe.tags = []
        recipe.image = Data()
        recipe.recurrenceIntervalDays = rhythmDays
        return recipe
    }

    private func feeding(_ recipe: Recipe, at date: Date, in context: NSManagedObjectContext) {
        let entry = StarterFeedingLog(context: context)
        entry.id = UUID()
        entry.date = date
        recipe.addToStarterFeedingLogs(entry)
    }

    @Test("Only recipes with a rhythm are starters, in name order")
    func startersAreRecipesWithARhythm() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        recipe("Weizensauer", rhythmDays: 7, in: context)
        recipe("Roggensauer", rhythmDays: 5, in: context)
        recipe("Baguette", rhythmDays: 0, in: context)
        try context.save()

        let names = try StarterFeedingStore.starterRecipes(in: context).map(\.name)
        #expect(names == ["Roggensauer", "Weizensauer"])
    }

    @Test("All fed at once: one entry each at the same time, a fresh one skipped")
    func feedAllSkipsTheOneJustLogged() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let roggen = recipe("Roggensauer", rhythmDays: 5, in: context)
        let weizen = recipe("Weizensauer", rhythmDays: 7, in: context)
        let lievito = recipe("Lievito Madre", rhythmDays: 3, in: context)
        feeding(roggen, at: now.addingTimeInterval(-15 * 60), in: context)      // just said "Roggensauer gefüttert"
        feeding(weizen, at: now.addingTimeInterval(-5 * 24 * 60 * 60), in: context)
        try context.save()

        let outcome = try StarterFeedingStore.logFeedings(
            for: try StarterFeedingStore.starterRecipes(in: context), at: now, note: "riecht gut", in: context
        )

        #expect(outcome.fed.map(\.name) == ["Lievito Madre", "Weizensauer"])
        #expect(outcome.alreadyLogged.map(\.name) == ["Roggensauer"])
        #expect(roggen.starterFeedingLogsArray.count == 1)
        #expect(weizen.starterFeedingLogsArray.first?.date == now)
        #expect(lievito.starterFeedingLogsArray.first?.date == now)
        #expect(lievito.starterFeedingLogsArray.first?.facts.note == "riecht gut")
    }

    @Test("A repeated request within the hour writes nothing")
    func repeatedRequestIsIdempotent() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let roggen = recipe("Roggensauer", rhythmDays: 5, in: context)
        try context.save()

        try StarterFeedingStore.logFeedings(for: [roggen], at: now, note: nil, in: context)
        let second = try StarterFeedingStore.logFeedings(for: [roggen], at: now.addingTimeInterval(30), note: nil, in: context)

        #expect(second.fed.isEmpty)
        #expect(second.alreadyLogged.count == 1)
        #expect(roggen.starterFeedingLogsArray.count == 1)
    }

    @Test("The entity carries the recipe's stable id and is found by it")
    func entityResolvesByRecipeID() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let roggen = recipe("Roggensauer", rhythmDays: 5, in: context)
        try context.save()

        let entity = StarterEntity(recipe: roggen)
        #expect(entity.id == roggen.id?.uuidString)
        #expect(entity.name == "Roggensauer")
        #expect(try StarterFeedingStore.starterRecipe(withID: entity.id, in: context) === roggen)
    }
}

// MARK: - Planned steps

@Suite("Which planned step Siri talks about")
@MainActor
struct PlannedStepStoreTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func minutes(_ offset: Int) -> Date {
        now.addingTimeInterval(TimeInterval(offset * 60))
    }

    @discardableResult
    private func step(_ instruction: String, at date: Date, number: Double, automatic: Bool = false,
                      in context: NSManagedObjectContext) -> NextStep {
        let step = NextStep(context: context)
        step.id = UUID()
        step.recipeName = "Brot"
        step.instruction = instruction
        step.step = number
        step.date = date
        step.planID = UUID()
        step.isAutomaticRecurrence = automatic
        return step
    }

    @Test("A step due within the last hour comes before the one ahead")
    func dueStepComesFirst() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        step("Teig falten", at: minutes(-20), number: 3, in: context)
        step("Formen", at: minutes(40), number: 4, in: context)
        try context.save()

        let current = try #require(try PlannedStepStore.currentStep(at: now, in: context))
        #expect(current.step.instruction == "Teig falten")
        #expect(current.isDue)
    }

    @Test("An old due step is let go of; the next one ahead counts")
    func oldDueStepIsLetGo() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        step("Teig falten", at: minutes(-90), number: 3, in: context)
        step("Formen", at: minutes(40), number: 4, in: context)
        try context.save()

        let current = try #require(try PlannedStepStore.currentStep(at: now, in: context))
        #expect(current.step.instruction == "Formen")
        #expect(!current.isDue)
    }

    @Test("Nothing to say without a plan, or with only a long-finished one")
    func noCurrentStep() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        #expect(try PlannedStepStore.currentStep(at: now, in: context) == nil)

        step("Backvorgang ist beendet", at: minutes(-3 * 60), number: 99, in: context)
        try context.save()
        #expect(try PlannedStepStore.currentStep(at: now, in: context) == nil)
    }

    @Test("Automatically queued steps far ahead stay out of sight")
    func automaticStepsFarAheadAreHidden() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        step("Anstellgut füttern", at: minutes(4 * 24 * 60), number: 1, automatic: true, in: context)
        try context.save()

        #expect(try PlannedStepStore.currentStep(at: now, in: context) == nil)
    }

    @Test("The oven question finds the bake, not the preheating")
    func ovenTimeIsTheBakingStep() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        step("Formen", at: minutes(10), number: 8, in: context)
        step("Backofen anstellen (250 °C)", at: minutes(60), number: 9.9, in: context)
        step("Brot bei 250 °C backen", at: minutes(120), number: 10, in: context)
        step("Backvorgang ist beendet", at: minutes(170), number: 99, in: context)
        try context.save()

        let bake = try #require(try PlannedStepStore.nextBakingStep(at: now, in: context))
        #expect(bake.instruction == "Brot bei 250 °C backen")
        #expect(bake.date == minutes(120))
    }

    @Test("Marking done removes the step from the plan")
    func markDoneRemovesTheStep() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let due = step("Teig falten", at: minutes(-10), number: 3, in: context)
        step("Formen", at: minutes(40), number: 4, in: context)
        try context.save()

        try PlannedStepStore.markDone(due, in: context)

        let remaining = try PlannedStepStore.visibleSteps(at: now, in: context).map(\.instruction)
        #expect(remaining == ["Formen"])
    }
}

// MARK: - Phrasing

@Suite("How Siri words a step")
struct IntentPhrasingTests {

    @Test("A component on its own line becomes a pause, not a line break")
    func componentLineBecomesAPause() {
        #expect(IntentPhrasing.spokenInstruction("Weizensauerteig\nZutaten mischen") == "Weizensauerteig, Zutaten mischen")
        #expect(IntentPhrasing.spokenInstruction("Teig falten") == "Teig falten")
        #expect(IntentPhrasing.spokenInstruction("  Formen \n\n") == "Formen")
    }

    @Test("Today, tomorrow and yesterday are named; further days spell the weekday")
    func relativeDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 09:00 Berlin
        let time = now.formatted(date: .omitted, time: .shortened)

        #expect(IntentPhrasing.dateText(now, now: now, calendar: calendar).contains(time))
        #expect(IntentPhrasing.dateText(now.addingTimeInterval(24 * 60 * 60), now: now, calendar: calendar)
                != IntentPhrasing.dateText(now, now: now, calendar: calendar))
        #expect(IntentPhrasing.dateText(now.addingTimeInterval(-24 * 60 * 60), now: now, calendar: calendar)
                != IntentPhrasing.dateText(now.addingTimeInterval(24 * 60 * 60), now: now, calendar: calendar))
    }
}
