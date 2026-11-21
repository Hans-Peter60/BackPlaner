//
//  KitchenCookRun.swift
//  BakePlannerCore
//
//  One time a dish was cooked against the clock: when each step was done
//  on the stopwatch, next to what the plan had said. Kept so the cook can
//  see where the time went — and later, so the estimates can learn from it.
//

import Foundation

public struct KitchenCookRun: Identifiable, Codable, Equatable, Sendable {

    public struct Step: Codable, Equatable, Sendable {
        public var taskID: String
        public var name: String
        public var component: String
        /// The step's planned length, hands and unattended, in minutes.
        public var plannedMinutes: Int
        /// Where the original plan put its start, in minutes from the start.
        public var plannedStart: Int
        /// Where the live plan had it begin when it was done, in seconds on
        /// the stopwatch: the start the actual time is measured from.
        public var startedSecond: Int
        /// When it was done, in seconds on the stopwatch.
        public var doneSecond: Int
        /// Ticked off by the cook, or ended by the clock (a pot that ran
        /// its time and was not ticked).
        public var tickedByCook: Bool

        public init(taskID: String, name: String, component: String, plannedMinutes: Int, plannedStart: Int,
                    startedSecond: Int, doneSecond: Int, tickedByCook: Bool) {
            self.taskID = taskID
            self.name = name
            self.component = component
            self.plannedMinutes = max(0, plannedMinutes)
            self.plannedStart = max(0, plannedStart)
            self.startedSecond = max(0, startedSecond)
            self.doneSecond = max(self.startedSecond, doneSecond)
            self.tickedByCook = tickedByCook
        }

        /// How long the step took, in seconds.
        public var actualSeconds: Int { doneSecond - startedSecond }

        /// Seconds more (positive) or less (negative) than planned.
        public var differenceSeconds: Int { actualSeconds - plannedMinutes * 60 }
    }

    public var id: String
    public var dishID: String
    public var dishName: String
    public var startedAt: Date
    /// The stopwatch at the end, pauses not counted.
    public var totalSeconds: Int
    /// What the plan said the dish would take, in minutes.
    public var plannedMinutes: Int
    /// The steps in the order they were done.
    public var steps: [Step]
    /// How many steps the dish has; fewer done means cooking was ended
    /// early. Nil in records from before it was kept.
    public var totalSteps: Int?

    public init(id: String = UUID().uuidString, dishID: String, dishName: String, startedAt: Date,
                totalSeconds: Int, plannedMinutes: Int, steps: [Step], totalSteps: Int? = nil) {
        self.totalSteps = totalSteps
        self.id = id
        self.dishID = dishID
        self.dishName = dishName
        self.startedAt = startedAt
        self.totalSeconds = max(0, totalSeconds)
        self.plannedMinutes = max(0, plannedMinutes)
        self.steps = steps.sorted { ($0.doneSecond, $0.taskID) < ($1.doneSecond, $1.taskID) }
    }

    /// Whether every step of the dish was done.
    public var isComplete: Bool { totalSteps.map { steps.count >= $0 } ?? true }

    /// "12:34" for seconds on the stopwatch; "1:02:03" from an hour on.
    public static func clockText(_ seconds: Int) -> String {
        let value = max(0, seconds)
        let hours = value / 3600, minutes = value / 60 % 60, rest = value % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// "+1:20" or "−0:45" for a difference in seconds; "±0:00" for none.
    public static func differenceText(_ seconds: Int) -> String {
        if seconds == 0 { return "±0:00" }
        return (seconds > 0 ? "+" : "−") + clockText(abs(seconds))
    }
}
