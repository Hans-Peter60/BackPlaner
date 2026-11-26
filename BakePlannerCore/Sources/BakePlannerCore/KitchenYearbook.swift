//
//  KitchenYearbook.swift
//  BakePlannerCore
//
//  A year of cooking, summed up for CookPlanner's yearbook PDF: the figures
//  of the year, the sessions month by month, the dishes cooked most, and
//  what the clock taught — where the cook got faster. The sums live here
//  with their tests; the drawing is the app's.
//

import Foundation

public struct KitchenYearbook: Equatable {

    public struct Month: Equatable {
        /// The first day of the month.
        public let start: Date
        public let runs: [KitchenCookRun]
    }

    public struct Favourite: Equatable, Sendable {
        public let dishID: String
        public let name: String
        public let count: Int
        public let averageRating: Double?
        /// The run whose photo stands for the dish: the best rated with one.
        public let photoRunID: String?
        /// The quickest complete run on the clock, in minutes.
        public let bestMinutes: Int?
        public let plannedMinutes: Int?
    }

    /// A dish the cook got quicker (or slower) at: the first and the latest
    /// complete run on the clock in the year.
    public struct Lesson: Equatable, Sendable {
        public let dishID: String
        public let name: String
        public let firstMinutes: Int
        public let latestMinutes: Int
        public var savedMinutes: Int { firstMinutes - latestMinutes }
    }

    public static let favouriteCount = 5

    public let year: Int
    /// Sessions in the year, manual entries included.
    public let sessions: Int
    /// Distinct days with a session.
    public let cookingDays: Int
    /// Distinct dishes cooked.
    public let dishes: Int
    /// Hours on the clock, over the runs with a stopwatch.
    public let hoursOnTheClock: Double
    public let averageRating: Double?
    /// Runs cooked against the clock, and how many of them within the plan.
    public let timedRuns: Int
    public let withinPlan: Int
    public let relaxedRuns: Int
    public let longestSession: (name: String, minutes: Int)?
    /// Twelve counts, January first.
    public let monthCounts: [Int]
    /// Only the months with sessions, January first.
    public let months: [Month]
    public let favourites: [Favourite]
    public let lessons: [Lesson]
    /// The run whose photo goes on the cover: the best rated with a photo,
    /// else the most-cooked dish's, else the first photo at all.
    public let coverPhotoRunID: String?

    public var isEmpty: Bool { sessions == 0 }

    public static func == (lhs: KitchenYearbook, rhs: KitchenYearbook) -> Bool {
        lhs.year == rhs.year && lhs.sessions == rhs.sessions && lhs.monthCounts == rhs.monthCounts
            && lhs.favourites == rhs.favourites && lhs.coverPhotoRunID == rhs.coverPhotoRunID
    }

    /// The years with a session, newest first.
    public static func years(of runs: [KitchenCookRun], now: Date = Date(), calendar: Calendar = .current) -> [Int] {
        Array(Set(runs.filter { $0.startedAt <= now }.map { calendar.component(.year, from: $0.startedAt) })).sorted(by: >)
    }

    public static func compute(year: Int, runs: [KitchenCookRun], now: Date = Date(),
                               calendar: Calendar = .current) -> KitchenYearbook {
        let ofYear = runs
            .filter { $0.startedAt <= now && calendar.component(.year, from: $0.startedAt) == year }
            .sorted { $0.startedAt < $1.startedAt }
        let days = Set(ofYear.map { calendar.startOfDay(for: $0.startedAt) })
        let timed = ofYear.filter { !$0.isManualEntry }
        let hours = Double(timed.reduce(0) { $0 + $1.totalSeconds }) / 3_600
        let ratings = ofYear.compactMap(\.rating).filter { (1...5).contains($0) }
        let averageRating = ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)
        let complete = timed.filter { $0.isComplete && $0.plannedMinutes > 0 && $0.relaxed != true }
        let withinPlan = complete.filter { $0.totalSeconds <= $0.plannedMinutes * 60 }.count
        let longest = timed.max { a, b in (a.totalSeconds, b.dishName) < (b.totalSeconds, a.dishName) }

        var monthCounts = Array(repeating: 0, count: 12)
        var byMonth: [Int: [KitchenCookRun]] = [:]
        for run in ofYear {
            let month = calendar.component(.month, from: run.startedAt)
            guard monthCounts.indices.contains(month - 1) else { continue }
            monthCounts[month - 1] += 1
            byMonth[month, default: []].append(run)
        }
        let months: [Month] = (1...12).compactMap { month in
            guard let runs = byMonth[month],
                  let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
            return Month(start: start, runs: runs)
        }

        let byDish = Dictionary(grouping: ofYear, by: \.dishID)
        let favourites: [Favourite] = byDish
            .map { id, runs in
                let stars = runs.compactMap(\.rating)
                let onClock = runs.filter { !$0.isManualEntry && $0.isComplete && $0.relaxed != true }
                return Favourite(
                    dishID: id,
                    name: runs.last?.dishName ?? "",
                    count: runs.count,
                    averageRating: stars.isEmpty ? nil : Double(stars.reduce(0, +)) / Double(stars.count),
                    photoRunID: bestPhoto(of: runs),
                    bestMinutes: onClock.map { ($0.totalSeconds + 59) / 60 }.min(),
                    plannedMinutes: onClock.last?.plannedMinutes)
            }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
            .prefix(favouriteCount)
            .map { $0 }

        let lessons: [Lesson] = byDish.compactMap { id, runs -> Lesson? in
            let onClock = runs.filter { !$0.isManualEntry && $0.isComplete && $0.relaxed != true }
            guard onClock.count >= 2, let first = onClock.first, let latest = onClock.last else { return nil }
            let before = (first.totalSeconds + 59) / 60, after = (latest.totalSeconds + 59) / 60
            guard abs(before - after) >= 2 else { return nil }
            return Lesson(dishID: id, name: latest.dishName, firstMinutes: before, latestMinutes: after)
        }
        .sorted { ($0.savedMinutes, $1.name) > ($1.savedMinutes, $0.name) }

        let cover = bestPhoto(of: ofYear)
            ?? favourites.first?.photoRunID
            ?? ofYear.first { $0.photoFileName != nil }?.id

        return KitchenYearbook(year: year, sessions: ofYear.count, cookingDays: days.count, dishes: byDish.count,
                               hoursOnTheClock: hours, averageRating: averageRating, timedRuns: complete.count,
                               withinPlan: withinPlan, relaxedRuns: ofYear.filter { $0.relaxed == true }.count,
                               longestSession: longest.map { ($0.dishName, ($0.totalSeconds + 59) / 60) },
                               monthCounts: monthCounts, months: months, favourites: favourites, lessons: lessons,
                               coverPhotoRunID: cover)
    }

    /// The run with a photo and the best rating; unrated counts as nothing,
    /// the earlier run wins a tie.
    static func bestPhoto(of runs: [KitchenCookRun]) -> String? {
        runs.filter { $0.photoFileName != nil }
            .max { a, b in (a.rating ?? 0, b.startedAt) < (b.rating ?? 0, a.startedAt) }?
            .id
    }
}
