//
//  BakeHistoryStoreContractTests.swift
//  BakePlannerCoreTests
//
//  The bake history store contract, checked against the in-memory store.
//  The Core Data and SQLite stores run the same checks.
//

import BakePlannerCore
import Foundation
import Testing

@Suite("Bake history store contract: in memory")
struct InMemoryBakeHistoryStoreTests {

    @Test("Every check of the contract", arguments: BakeHistoryStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(BakeHistoryStoreContract.checks.first { $0.name == name })
        let recipes = InMemoryRecipeStore()
        try check.run(InMemoryBakeHistoryStore(recipes: recipes), recipes)
    }

    @Test("Normalized facts trim the texts and drop proofs of no length; 0 °C stays")
    func normalized() {
        let facts = BakeHistoryFacts(roomTemperature: 0, bulkProofMinutes: 0, finalProofMinutes: 30,
                                     flour: " Roggen 1150 ", outcome: "")
        #expect(facts.normalized == BakeHistoryFacts(roomTemperature: 0, finalProofMinutes: 30, flour: "Roggen 1150"))
    }
}
