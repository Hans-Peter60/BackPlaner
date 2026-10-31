//
//  ScheduledStepStoreContractTests.swift
//  BakePlannerCoreTests
//
//  The scheduled step store contract, checked against the in-memory store.
//  The Core Data and SQLite stores run the same checks.
//

import BakePlannerCore
import Testing

@Suite("Scheduled step store contract: in memory")
struct InMemoryScheduledStepStoreTests {

    @Test("Every check of the contract", arguments: ScheduledStepStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(ScheduledStepStoreContract.checks.first { $0.name == name })
        try check.run(InMemoryScheduledStepStore())
    }
}
