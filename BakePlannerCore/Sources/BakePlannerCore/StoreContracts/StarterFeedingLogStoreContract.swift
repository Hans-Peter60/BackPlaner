//
//  StarterFeedingLogStoreContract.swift
//  BakePlannerCore
//
//  What every StarterFeedingLogStore must do, written once and checked
//  against each store: in memory, Core Data, SQLite. Each check takes a new,
//  empty store and the recipe store kept beside it, and throws
//  ContractViolation when the store behaves differently.
//

import Foundation

public enum StarterFeedingLogStoreContract {

    public typealias Check = (StarterFeedingLogStore, RecipeStore) throws -> Void

    /// Every check by name, for running them one by one.
    public static let checks: [(name: String, run: Check)] = [
        ("an empty store has nothing", emptyStore),
        ("a feeding comes back as it was added", addAndRead),
        ("facts are kept normalized; not measured stays apart from failed", normalizedFacts),
        ("feedings come newest first, each recipe its own", order),
        ("the result is entered afterwards; date and recipe stay", update),
        ("a removed feeding is gone, the others stay", delete),
        ("removing a recipe removes its feedings", recipeRemoved),
        ("unknown keys are reported, not ignored", unknownKeys),
    ]

    // MARK: Checks

    public static func emptyStore(_ store: StarterFeedingLogStore, _ recipes: RecipeStore) throws {
        try expect(store.feedings(ofRecipe: "none").isEmpty, "an empty store has feedings of an unknown recipe")
        let starter = try newRecipe(recipes)
        try expect(store.feedings(ofRecipe: starter.id).isEmpty, "a new recipe has feedings")
    }

    public static func addAndRead(_ store: StarterFeedingLogStore, _ recipes: RecipeStore) throws {
        let starter = try newRecipe(recipes)
        let facts = StarterFeedingFacts(peakMinutes: 270, floatTestPassed: true, note: "Riecht säuerlich – „gut“")
        let added = try store.add(toRecipe: starter.id, date: moment(10), facts: facts)

        try expect(!added.id.isEmpty, "the new feeding has no key")
        try expect(added.recipeID == starter.id && added.date == moment(10) && added.facts == facts,
                   "add returns other content than it was given")
        try expect(store.feedings(ofRecipe: starter.id) == [added], "the recipe's feedings differ from the one added")
        try expect(recipes.recipe(id: starter.id)?.bakeHistoryFlag == false, "a feeding marked the recipe as baked")
    }

    public static func normalizedFacts(_ store: StarterFeedingLogStore, _ recipes: RecipeStore) throws {
        let starter = try newRecipe(recipes)
        let failed = try store.add(toRecipe: starter.id, date: moment(10),
                                   facts: StarterFeedingFacts(peakMinutes: 0, floatTestPassed: false, note: "  träge \n"))
        let untested = try store.add(toRecipe: starter.id, date: moment(11),
                                     facts: StarterFeedingFacts(peakMinutes: -3, floatTestPassed: nil, note: ""))

        try expect(failed.facts == StarterFeedingFacts(floatTestPassed: false, note: "träge"),
                   "add does not normalize the facts: \(failed.facts)")
        try expect(untested.facts == StarterFeedingFacts(), "add does not normalize the facts: \(untested.facts)")
        try expect(store.feedings(ofRecipe: starter.id) == [untested, failed],
                   "the stored facts differ from the normalized ones")
    }

    public static func order(_ store: StarterFeedingLogStore, _ recipes: RecipeStore) throws {
        let rye = try newRecipe(recipes)
        let wheat = try newRecipe(recipes, name: "Weizensauer")
        let middle = try store.add(toRecipe: rye.id, date: moment(12), facts: StarterFeedingFacts())
        let other = try store.add(toRecipe: wheat.id, date: moment(13), facts: StarterFeedingFacts())
        let oldest = try store.add(toRecipe: rye.id, date: moment(10), facts: StarterFeedingFacts())
        let newest = try store.add(toRecipe: rye.id, date: moment(14), facts: StarterFeedingFacts(peakMinutes: 300))

        try expect(store.feedings(ofRecipe: rye.id) == [newest, middle, oldest],
                   "the recipe's feedings are not its own, newest first")
        try expect(store.feedings(ofRecipe: wheat.id) == [other], "the other recipe's feedings are not its own")
    }

    public static func update(_ store: StarterFeedingLogStore, _ recipes: RecipeStore) throws {
        let rye = try newRecipe(recipes)
        let wheat = try newRecipe(recipes, name: "Weizensauer")
        // As planning writes it: the start, no result yet.
        let planned = try store.add(toRecipe: rye.id, date: moment(10), facts: StarterFeedingFacts())
        let other = try store.add(toRecipe: rye.id, date: moment(8), facts: StarterFeedingFacts(note: "Gut"))

        var result = planned
        result.facts = StarterFeedingFacts(peakMinutes: 0, floatTestPassed: false, note: " träge ")
        result.date = moment(20)
        result.recipeID = wheat.id
        try store.update(result)

        var expected = planned
        expected.facts = StarterFeedingFacts(floatTestPassed: false, note: "träge")
        try expect(store.feedings(ofRecipe: rye.id) == [expected, other],
                   "the result was not entered as normalized, or date, recipe or the other feeding changed")
        try expect(store.feedings(ofRecipe: wheat.id).isEmpty, "the update moved the feeding")

        result.facts = StarterFeedingFacts(peakMinutes: 285, floatTestPassed: true)
        try store.update(result)
        try expect(store.feedings(ofRecipe: rye.id).first?.facts == StarterFeedingFacts(peakMinutes: 285, floatTestPassed: true),
                   "a second result did not replace the first")
    }

    public static func delete(_ store: StarterFeedingLogStore, _ recipes: RecipeStore) throws {
        let starter = try newRecipe(recipes)
        let first = try store.add(toRecipe: starter.id, date: moment(10), facts: StarterFeedingFacts())
        let second = try store.add(toRecipe: starter.id, date: moment(11), facts: StarterFeedingFacts(note: "Gut"))

        try store.delete(id: first.id)
        try expect(store.feedings(ofRecipe: starter.id) == [second], "the removed feeding is still there, or more went")
        try expect(recipes.recipe(id: starter.id) != nil, "removing a feeding removed its recipe")
        try store.delete(id: first.id)
    }

    public static func recipeRemoved(_ store: StarterFeedingLogStore, _ recipes: RecipeStore) throws {
        let rye = try newRecipe(recipes)
        let wheat = try newRecipe(recipes, name: "Weizensauer")
        _ = try store.add(toRecipe: rye.id, date: moment(10), facts: StarterFeedingFacts())
        let kept = try store.add(toRecipe: wheat.id, date: moment(11), facts: StarterFeedingFacts())

        try recipes.delete(id: rye.id)

        try expect(store.feedings(ofRecipe: rye.id).isEmpty, "the removed recipe still has feedings")
        try expect(store.feedings(ofRecipe: wheat.id) == [kept], "the other recipe's feeding went too")
    }

    public static func unknownKeys(_ store: StarterFeedingLogStore, _ recipes: RecipeStore) throws {
        do {
            _ = try store.add(toRecipe: "none", date: moment(10), facts: StarterFeedingFacts())
            throw ContractViolation(description: "adding a feeding to an unknown recipe did not fail")
        } catch StarterFeedingLogStoreError.unknownRecipe {}
        do {
            try store.update(StoredStarterFeeding(id: "none", recipeID: "none", date: moment(10)))
            throw ContractViolation(description: "entering the result of an unknown feeding did not fail")
        } catch StarterFeedingLogStoreError.unknownFeeding {}
        let starter = try newRecipe(recipes)
        let feeding = try store.add(toRecipe: starter.id, date: moment(10), facts: StarterFeedingFacts())
        try store.delete(id: "none")
        try expect(store.feedings(ofRecipe: starter.id) == [feeding], "an unknown key removed a feeding")
    }

    // MARK: Helpers

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw ContractViolation(description: message()) }
    }

    private static func newRecipe(_ recipes: RecipeStore, name: String = "Roggensauer") throws -> StoredRecipe {
        var content = RecipeStoreContract.bread()
        content.name = name
        return try recipes.add(content, firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
    }

    /// A moment in November 2026, on whole seconds, `hour` hours in.
    private static func moment(_ hour: Int) -> Date {
        Date(timeIntervalSince1970: 1_793_520_000 + Double(hour) * 3_600)
    }
}
