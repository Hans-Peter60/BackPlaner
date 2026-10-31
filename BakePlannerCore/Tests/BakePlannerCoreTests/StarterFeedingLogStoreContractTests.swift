//
//  StarterFeedingLogStoreContractTests.swift
//  BakePlannerCoreTests
//
//  The starter feeding diary contract, checked against the in-memory store.
//  The Core Data and SQLite stores run the same checks.
//

import BakePlannerCore
import Testing

@Suite("Starter feeding diary contract: in memory")
struct InMemoryStarterFeedingLogStoreTests {

    @Test("Every check of the contract", arguments: StarterFeedingLogStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(StarterFeedingLogStoreContract.checks.first { $0.name == name })
        let recipes = InMemoryRecipeStore()
        try check.run(InMemoryStarterFeedingLogStore(recipes: recipes), recipes)
    }

    @Test("Normalized facts trim the note and drop a peak time of no length; a failed float test stays")
    func normalized() {
        let facts = StarterFeedingFacts(peakMinutes: 0, floatTestPassed: false, note: " träge ")
        #expect(facts.normalized == StarterFeedingFacts(floatTestPassed: false, note: "träge"))
    }
}
