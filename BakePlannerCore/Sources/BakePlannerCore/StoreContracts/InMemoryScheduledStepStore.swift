//
//  InMemoryScheduledStepStore.swift
//  BakePlannerCore
//
//  A ScheduledStepStore that keeps everything in memory: the reference the
//  contract is checked against first, and a stand-in for testing the
//  planning logic without Core Data or SQLite.
//

import Foundation

public final class InMemoryScheduledStepStore: ScheduledStepStore {

    private var entries: [StoredScheduledStep] = []
    private var nextKey = 1

    public init(_ steps: [ScheduledStepData] = []) {
        add(steps)
    }

    /// The steps as they were added.
    public var stored: [ScheduledStepData] { entries.map(\.data) }

    public func steps(excludingRecipe recipeName: String) -> [ScheduledStepData] {
        stored.filter { $0.recipeName != recipeName }
    }

    public func hasSteps(recipeName: String) -> Bool {
        stored.contains { $0.recipeName == recipeName }
    }

    public func hasSteps(recipeName: String, onOrAfter date: Date) -> Bool {
        stored.contains { $0.recipeName == recipeName && $0.date >= date }
    }

    public func add(_ steps: [ScheduledStepData]) {
        for step in steps {
            entries.append(StoredScheduledStep(key: "memory-step-\(nextKey)", data: step))
            nextKey += 1
        }
    }

    public func removeSteps(recipeName: String) {
        entries.removeAll { $0.data.recipeName == recipeName }
    }

    public func allSteps() -> [StoredScheduledStep] {
        entries.sorted { first, second in
            if first.data.date != second.data.date { return first.data.date < second.data.date }
            return first.data.step < second.data.step
        }
    }

    public func removeStep(key: String) {
        entries.removeAll { $0.key == key }
    }

    public func setDates(_ dates: [String: Date]) {
        for index in entries.indices {
            if let date = dates[entries[index].key] {
                entries[index].data.date = date
            }
        }
    }
}
