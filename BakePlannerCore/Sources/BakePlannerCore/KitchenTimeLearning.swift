//
//  KitchenTimeLearning.swift
//  BakePlannerCore
//
//  New minutes for a dish's steps from the stopwatch records of the times
//  it was cooked: per step the median of what it took in the latest runs,
//  proposed where it differs from the plan by a minute or more. The cook
//  decides; nothing is changed on its own.
//

import Foundation

public enum KitchenTimeLearning {

    /// How many of the latest runs count.
    public static let runsConsidered = 5

    public struct Suggestion: Equatable, Sendable {
        public let taskID: String
        public let name: String
        public let handsBefore: Int
        public let unattendedBefore: Int
        public let hands: Int
        public let unattended: Int
        /// In how many runs the step was ticked.
        public let runs: Int
    }

    /// The proposals for `dish` from `runs` (newest first, as the log keeps
    /// them). Only steps the cook ticked count: a pot that ran its time
    /// teaches nothing. A step without an unattended part learns its hands
    /// minutes; one with an unattended part keeps its hands and learns the
    /// rest — a pot taken off early, or one that needed longer. Runs cooked
    /// in the relaxed mode, with no clock to cook against, do not count.
    public static func suggestions(for dish: KitchenDish, from runs: [KitchenCookRun]) -> [Suggestion] {
        let latest = runs.filter { $0.dishID == dish.id && $0.relaxed != true }.prefix(runsConsidered)
        guard !latest.isEmpty else { return [] }
        return dish.tasks.compactMap { task in
            let seconds = latest.compactMap { run in
                run.steps.first { $0.taskID == task.id && $0.tickedByCook }?.actualSeconds
            }
            guard !seconds.isEmpty else { return nil }
            let minutes = max(1, Int((median(seconds) / 60).rounded()))
            let hands: Int, unattended: Int
            if task.unattendedMinutes == 0 {
                hands = minutes
                unattended = 0
            } else {
                hands = task.handsMinutes
                unattended = max(0, minutes - task.handsMinutes)
            }
            guard hands != task.handsMinutes || unattended != task.unattendedMinutes else { return nil }
            return Suggestion(taskID: task.id, name: task.name, handsBefore: task.handsMinutes,
                              unattendedBefore: task.unattendedMinutes, hands: hands, unattended: unattended,
                              runs: seconds.count)
        }
    }

    /// `dish` with `suggestions` applied; a window widens to hold the new
    /// unattended time.
    public static func applying(_ suggestions: [Suggestion], to dish: KitchenDish) -> KitchenDish {
        var result = dish
        result.tasks = dish.tasks.map { task in
            guard let suggestion = suggestions.first(where: { $0.taskID == task.id }) else { return task }
            let window = task.unattendedWindow.map {
                min($0.lowerBound, suggestion.unattended)...max($0.upperBound, suggestion.unattended)
            }
            return KitchenTask(id: task.id, name: task.name, component: task.component,
                               hands: suggestion.hands, unattended: suggestion.unattended, station: task.station,
                               after: task.after, maxWait: task.maxWait, window: window,
                               ovenTemperature: task.ovenTemperature, ingredientIDs: task.ingredientIDs)
        }
        return result
    }

    static func median(_ values: [Int]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? Double(sorted[middle]) : Double(sorted[middle - 1] + sorted[middle]) / 2
    }
}
