//
//  SQLiteScheduledStepStoreTests.swift
//  BakePlannerStorageTests
//
//  The scheduled step store contract, checked against SQLite: the same
//  checks the in-memory store passes in BakePlannerCore and the Core Data
//  store in the iOS app. Runs on the Mac (swift test) and on Android
//  (skip android test).
//

import BakePlannerCore
import BakePlannerStorage
import Foundation
import Testing

@Suite("Scheduled step store contract: SQLite")
struct SQLiteScheduledStepStoreTests {

    @Test("Every check of the contract", arguments: ScheduledStepStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(ScheduledStepStoreContract.checks.first { $0.name == name })
        let recipes = try SQLiteRecipeStore(path: nil)
        defer { try? recipes.close() }
        try check.run(SQLiteScheduledStepStore(file: recipes.file))
    }

    @Test("Steps stay in the database file when it is closed and opened again")
    func persistence() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("steps-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let step = ScheduledStepData(id: UUID(), planID: UUID(), recipeName: "Roggensauer",
                                     instruction: "Bei 26 °C 12 Stunden reifen lassen", step: 2, startTime: 5,
                                     duration: 720, date: Date(timeIntervalSinceReferenceDate: 815_000_000.5),
                                     isAutomaticRecurrence: true, servingScale: 1.5)
        let first = try SQLiteRecipeStore(path: path)
        SQLiteScheduledStepStore(file: first.file).add([step])
        try first.close()

        let second = try SQLiteRecipeStore(path: path)
        defer { try? second.close() }
        #expect(SQLiteScheduledStepStore(file: second.file).allSteps().map(\.data) == [step])
    }
}
