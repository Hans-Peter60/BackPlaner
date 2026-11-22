//
//  KitchenCookStatistics.swift
//  BakePlannerCore
//
//  What CookPlanner's cooking history adds up to, the way BakeStatistics
//  sums up BakePlanner's: how often, how many dishes, the stars, the
//  months, the dishes cooked most and the hit list by stars, and — from
//  the stopwatch runs — how far the cook was ahead of or behind the plan.
//  A run without steps is an entry made by hand or from a photo.
//

import Foundation

extension KitchenCookRun {

    /// Entered by hand or from a photo: no stopwatch behind it.
    public var isManualEntry: Bool { steps.isEmpty && totalSeconds == 0 }

    /// A dish cooked without the stopwatch, as the history keeps it.
    public static func manualEntry(dishID: String, dishName: String, date: Date,
                                   rating: Int? = nil, note: String? = nil) -> KitchenCookRun {
        var run = KitchenCookRun(dishID: dishID, dishName: dishName, startedAt: date,
                                 totalSeconds: 0, plannedMinutes: 0, steps: [])
        run.rating = rating.map { min(5, max(1, $0)) }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        run.note = trimmed.isEmpty ? nil : trimmed
        return run
    }
}

public struct KitchenCookStatistics: Equatable, Sendable {

    public struct MonthCount: Identifiable, Equatable, Sendable {
        /// The first day of the month.
        public let month: Date
        public let count: Int
        public var id: Date { month }
    }

    public struct DishCount: Identifiable, Equatable, Sendable {
        public let dishID: String
        public let name: String
        public let count: Int
        public let lastDate: Date
        /// The average of the given stars; nil without any.
        public let averageRating: Double?
        public var id: String { dishID }
    }

    /// Every entry, by stopwatch or by hand.
    public let total: Int
    /// How many different dishes.
    public let dishCount: Int
    public let averageRating: Double?
    /// The complete stopwatch runs and their mean against the plan, in
    /// minutes: positive is slower than planned.
    public let timedRuns: Int
    public let averageMinutesOverPlan: Double?
    /// The last twelve months, oldest first, empty months included.
    public let months: [MonthCount]
    /// The dishes by how often they were cooked, then by the latest.
    public let mostCooked: [DishCount]
    /// The rated dishes by their stars, then by how often.
    public let hitList: [DishCount]

    public init(runs: [KitchenCookRun], now: Date = Date(), calendar: Calendar = .current) {
        total = runs.count
        let ratings = runs.compactMap(\.rating)
        averageRating = ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)
        let timed = runs.filter { !$0.isManualEntry && $0.isComplete && $0.plannedMinutes > 0 }
        timedRuns = timed.count
        averageMinutesOverPlan = timed.isEmpty ? nil
            : timed.map { Double($0.totalSeconds - $0.plannedMinutes * 60) / 60 }.reduce(0, +) / Double(timed.count)

        // A dish is known by its id; its name is the one of its latest run.
        let byDish = Dictionary(grouping: runs, by: \.dishID)
        let counts: [DishCount] = byDish.map { id, dishRuns in
            let latest = dishRuns.max { $0.startedAt < $1.startedAt }!
            let stars = dishRuns.compactMap(\.rating)
            return DishCount(dishID: id, name: latest.dishName, count: dishRuns.count, lastDate: latest.startedAt,
                             averageRating: stars.isEmpty ? nil : Double(stars.reduce(0, +)) / Double(stars.count))
        }
        dishCount = counts.count
        mostCooked = counts.sorted { ($0.count, $0.lastDate) > ($1.count, $1.lastDate) }
        hitList = counts.filter { $0.averageRating != nil }
            .sorted { (($0.averageRating ?? 0), $0.count, $0.lastDate) > (($1.averageRating ?? 0), $1.count, $1.lastDate) }

        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        months = (0..<12).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .month, value: -back, to: thisMonth),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            return MonthCount(month: start, count: runs.filter { $0.startedAt >= start && $0.startedAt < end }.count)
        }
    }
}
