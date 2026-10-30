//
//  RecipeStoreContractTests.swift
//  BakePlannerCoreTests
//
//  The recipe store contract, checked against the in-memory store. The
//  Core Data and SQLite stores run the same checks.
//

import BakePlannerCore
import Testing

@Suite("Recipe store contract: in memory")
struct InMemoryRecipeStoreTests {

    @Test("Every check of the contract", arguments: RecipeStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(RecipeStoreContract.checks.first { $0.name == name })
        try check.run(InMemoryRecipeStore())
    }
}
