//
//  ScheduledStepShift.swift
//  BakePlannerCore
//
//  Moving a planned step — "Schritt verschieben" — and, if asked, the steps
//  that follow it in its plan, by the same time. The same rule the iPhone
//  applies through a Core Data fetch (NotificationActions.
//  followingStepsPredicate), as plain logic Android uses too.
//

import Foundation

public enum ScheduledStepShift {

    public enum Failure: Error, Equatable {
        /// The step would land at or before now.
        case dateInPast
        /// No step has this key (any more).
        case unknownStep
    }

    /// Whether `candidate` follows `step` in its plan: the same plan (the
    /// same plan id; steps stored before plans had one belong together by
    /// recipe name), and later — or at the same minute with a higher step
    /// number, so the finish ("Backvorgang ist beendet", step 99) goes with
    /// the bake while the oven step at the bake's minute stays.
    public static func follows(_ candidate: ScheduledStepData, _ step: ScheduledStepData) -> Bool {
        guard candidate.recipeName == step.recipeName, candidate.planID == step.planID else { return false }
        if candidate.date > step.date { return true }
        return candidate.date == step.date && candidate.step > step.step
    }

    /// The new dates, by key, when the step `key` moves by `minutes` (negative
    /// for earlier) — with its followers if `includeFollowing`. The followers
    /// are found on the dates before the move and keep their spacing.
    public static func newDates(shifting key: String, byMinutes minutes: Int, includeFollowing: Bool,
                                in steps: [StoredScheduledStep], now: Date = Date()) throws -> [String: Date] {
        guard let moved = steps.first(where: { $0.key == key }) else { throw Failure.unknownStep }
        let shift = TimeInterval(minutes * 60)
        let newDate = moved.data.date.addingTimeInterval(shift)
        guard newDate > now else { throw Failure.dateInPast }

        var dates = [key: newDate]
        if includeFollowing {
            for step in steps where step.key != key && follows(step.data, moved.data) {
                dates[step.key] = step.data.date.addingTimeInterval(shift)
            }
        }
        return dates
    }
}
