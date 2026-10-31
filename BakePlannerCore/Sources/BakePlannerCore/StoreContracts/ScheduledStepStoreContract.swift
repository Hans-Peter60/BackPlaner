//
//  ScheduledStepStoreContract.swift
//  BakePlannerCore
//
//  What every ScheduledStepStore must do, written once and checked against
//  each store: in memory, Core Data, SQLite. Each check takes a new, empty
//  store and throws ContractViolation when the store behaves differently.
//

import Foundation

public enum ScheduledStepStoreContract {

    /// Every check by name, for running them one by one.
    public static let checks: [(name: String, run: (ScheduledStepStore) throws -> Void)] = [
        ("an empty store has nothing", emptyStore),
        ("steps come back with every field", roundTrip),
        ("all steps come by date, then by step number", order),
        ("a recipe's steps are found, with and without a date", hasSteps),
        ("the steps of other recipes are found without the recipe's own", excluding),
        ("removing a recipe's steps leaves the others", removeRecipe),
        ("a step done is removed on its own", removeStep),
        ("steps get new dates in one go, the others stay", setDates),
    ]

    // MARK: Checks

    public static func emptyStore(_ store: ScheduledStepStore) throws {
        try expect(store.allSteps().isEmpty, "an empty store has steps")
        try expect(store.steps(excludingRecipe: "Brot").isEmpty, "an empty store has steps of other recipes")
        try expect(!store.hasSteps(recipeName: "Brot"), "an empty store has steps of a recipe")
        store.removeStep(key: "none")
        store.removeSteps(recipeName: "Brot")
        try expect(store.allSteps().isEmpty, "removing from an empty store added steps")
    }

    public static func roundTrip(_ store: ScheduledStepStore) throws {
        let full = ScheduledStepData(id: UUID(), planID: UUID(), recipeName: "Landbrot – „Roggen“",
                                     instruction: "Bei 250 °C 50 Minuten backen", step: 2.5, startTime: 60,
                                     duration: 50, date: minute(60), isAutomaticRecurrence: true,
                                     servingScale: 1.37)
        // As steps stored before they had an id or a plan look.
        let old = ScheduledStepData(id: nil, planID: nil, recipeName: "Zopf", instruction: "Teig kneten",
                                    step: 1, startTime: 0, duration: 15, date: minute(0),
                                    isAutomaticRecurrence: false, servingScale: 0)
        store.add([full, old])

        let all = store.allSteps()
        try expect(all.map(\.data) == [old, full], "the steps read back differ: \(all.map(\.data))")
        try expect(all.allSatisfy { !$0.key.isEmpty } && Set(all.map(\.key)).count == 2,
                   "the steps have no keys of their own")
        try expect(store.steps(excludingRecipe: "Zopf") == [full], "the steps of other recipes differ")
    }

    public static func order(_ store: ScheduledStepStore) throws {
        store.add([step("Brot", 3, at: 120), step("Brot", 1, at: 0), step("Kuchen", 4, at: 60),
                   step("Brot", 2, at: 60)])
        let all = store.allSteps().map(\.data)
        try expect(all.map(\.date) == [minute(0), minute(60), minute(60), minute(120)],
                   "the steps are not by date: \(all.map(\.date))")
        try expect(all.map(\.step) == [1, 2, 4, 3], "steps at the same time are not by step number")
    }

    public static func hasSteps(_ store: ScheduledStepStore) throws {
        store.add([step("Brot", 1, at: 0), step("Brot", 2, at: 60)])
        try expect(store.hasSteps(recipeName: "Brot"), "the recipe's steps are not found")
        try expect(!store.hasSteps(recipeName: "Kuchen"), "another recipe has steps")
        try expect(store.hasSteps(recipeName: "Brot", onOrAfter: minute(60)), "a step at the date is not found")
        try expect(!store.hasSteps(recipeName: "Brot", onOrAfter: minute(61)), "a step after the date is found")
    }

    public static func excluding(_ store: ScheduledStepStore) throws {
        let kuchen = step("Kuchen", 1, at: 30)
        store.add([step("Brot", 1, at: 0), kuchen, step("Brot", 2, at: 60)])
        try expect(store.steps(excludingRecipe: "Brot") == [kuchen], "the steps of other recipes differ")
        try expect(store.steps(excludingRecipe: "Zopf").count == 3, "an unknown recipe excludes steps")
    }

    public static func removeRecipe(_ store: ScheduledStepStore) throws {
        let kuchen = step("Kuchen", 1, at: 30)
        store.add([step("Brot", 1, at: 0), kuchen, step("Brot", 2, at: 60)])
        store.removeSteps(recipeName: "Brot")
        try expect(store.allSteps().map(\.data) == [kuchen], "removing the recipe's steps left others than expected")
        try expect(!store.hasSteps(recipeName: "Brot"), "the removed recipe still has steps")
    }

    public static func removeStep(_ store: ScheduledStepStore) throws {
        let first = step("Brot", 1, at: 0)
        let second = step("Brot", 2, at: 60)
        store.add([first, second])
        guard let key = store.allSteps().first?.key else {
            throw ContractViolation(description: "the added steps are missing")
        }
        store.removeStep(key: key)
        try expect(store.allSteps().map(\.data) == [second], "the step done is still there, or another went")
        store.removeStep(key: key)
        store.removeStep(key: "none")
        try expect(store.allSteps().map(\.data) == [second], "an unknown key removed a step")
    }

    public static func setDates(_ store: ScheduledStepStore) throws {
        let first = step("Brot", 1, at: 0)
        let second = step("Brot", 2, at: 60)
        let other = step("Kuchen", 1, at: 30)
        store.add([first, second, other])
        let keys = Dictionary(store.allSteps().map { ($0.data.recipeName + "\($0.data.step)", $0.key) },
                              uniquingKeysWith: { first, _ in first })
        guard let firstKey = keys["Brot1.0"], let secondKey = keys["Brot2.0"] else {
            throw ContractViolation(description: "the added steps are missing")
        }

        store.setDates([firstKey: minute(15), secondKey: minute(75), "none": minute(500)])

        var movedFirst = first
        movedFirst.date = minute(15)
        var movedSecond = second
        movedSecond.date = minute(75)
        try expect(store.allSteps().map(\.data) == [movedFirst, other, movedSecond],
                   "the new dates were not kept, or other steps changed: \(store.allSteps().map(\.data))")
        try expect(store.allSteps().map(\.key).contains(firstKey), "a step lost its key by moving")
        try expect(store.hasSteps(recipeName: "Brot", onOrAfter: minute(75)), "the moved date is not found")
    }

    // MARK: Helpers

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw ContractViolation(description: message()) }
    }

    private static func minute(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + Double(offset) * 60)
    }

    private static func step(_ recipe: String, _ number: Double, at offset: Int) -> ScheduledStepData {
        ScheduledStepData(id: UUID(), planID: nil, recipeName: recipe, instruction: "Schritt \(number)",
                          step: number, startTime: offset, duration: 0, date: minute(offset),
                          isAutomaticRecurrence: false, servingScale: 1)
    }
}
