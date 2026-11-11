//
//  BakeStatistics.swift
//  BakePlannerCore
//
//  What the bake history adds up to: bakes per month, the recipes baked
//  most, the stars given, proofing times against the room temperature, and
//  the words used for crumb and oven spring. Pure arithmetic over the
//  entries, so both apps can draw the same figures.
//

import Foundation

public struct BakeStatistics: Equatable {

    /// One bake as the statistics read it: which recipe, when, and the facts.
    public struct Entry: Equatable {
        public let recipeName: String
        public let date: Date
        public let facts: BakeHistoryFacts

        public init(recipeName: String, date: Date, facts: BakeHistoryFacts) {
            self.recipeName = recipeName
            self.date = date
            self.facts = facts
        }
    }

    public struct MonthCount: Identifiable, Equatable, Sendable {
        /// The first moment of the month.
        public let month: Date
        public let count: Int
        public var id: Date { month }
    }

    public struct RecipeCount: Identifiable, Equatable, Sendable {
        public let name: String
        public let count: Int
        public let lastDate: Date
        /// The mean of the stars given to this recipe's bakes; nil without any.
        public let averageRating: Double?
        public var id: String { name }
    }

    /// A bake with a room temperature and a measured proof.
    public struct ProofPoint: Identifiable, Equatable, Sendable {
        public let id: Int
        public let recipeName: String
        public let date: Date
        public let temperature: Double
        public let minutes: Int
    }

    public struct OutcomeCount: Identifiable, Equatable, Sendable {
        public let keyword: String
        public let count: Int
        public var id: String { keyword }
    }

    /// How many months the per-month chart covers, the current one included.
    public static let chartMonths = 12

    /// Completed bakes: entries up to now. A planned bake in the future is
    /// not a bake yet.
    public let total: Int
    public let thisYear: Int
    public let firstDate: Date?
    /// Bakes per month since the first bake, over whole months.
    public let perMonth: Double
    /// The last `chartMonths` months, oldest first, with zeros for quiet months.
    public let months: [MonthCount]
    /// Every recipe baked, most often first.
    public let recipes: [RecipeCount]
    /// How many bakes got one to five stars; index 0 stays unused.
    public let ratingCounts: [Int]
    public let averageRating: Double?
    public let finalProofs: [ProofPoint]
    public let bulkProofs: [ProofPoint]
    /// The words for crumb and oven spring, most frequent first.
    public let outcomes: [OutcomeCount]

    public var isEmpty: Bool { total == 0 }

    public static func compute(entries: [Entry], now: Date = Date(), calendar: Calendar = .current) -> BakeStatistics {
        let completed = entries.filter { $0.date <= now }.sorted { $0.date < $1.date }
        let total = completed.count
        let firstDate = completed.first?.date

        let currentYear = calendar.component(.year, from: now)
        let thisYear = completed.filter { calendar.component(.year, from: $0.date) == currentYear }.count

        func monthStart(_ date: Date) -> Date {
            calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
        let currentMonth = monthStart(now)
        var countByMonth: [Date: Int] = [:]
        for entry in completed {
            countByMonth[monthStart(entry.date), default: 0] += 1
        }
        let months: [MonthCount] = (0..<chartMonths).reversed().compactMap { back in
            guard let month = calendar.date(byAdding: .month, value: -back, to: currentMonth) else { return nil }
            return MonthCount(month: month, count: countByMonth[month] ?? 0)
        }

        var perMonth = 0.0
        if let firstDate {
            let elapsed = calendar.dateComponents([.month], from: monthStart(firstDate), to: currentMonth).month ?? 0
            perMonth = Double(total) / Double(max(1, elapsed + 1))
        }

        var byRecipe: [String: (count: Int, last: Date, stars: [Int])] = [:]
        for entry in completed {
            var tally = byRecipe[entry.recipeName] ?? (0, entry.date, [])
            tally.count += 1
            tally.last = max(tally.last, entry.date)
            if let rating = entry.facts.rating { tally.stars.append(rating) }
            byRecipe[entry.recipeName] = tally
        }
        let recipes = byRecipe.map { name, tally in
            RecipeCount(name: name, count: tally.count, lastDate: tally.last,
                        averageRating: tally.stars.isEmpty ? nil : Double(tally.stars.reduce(0, +)) / Double(tally.stars.count))
        }
        .sorted { ($0.count, $0.lastDate, $1.name) > ($1.count, $1.lastDate, $0.name) }

        var ratingCounts = Array(repeating: 0, count: BakeHistoryFacts.maximumRating + 1)
        var ratingSum = 0
        var rated = 0
        for rating in completed.compactMap(\.facts.rating) where (1...BakeHistoryFacts.maximumRating).contains(rating) {
            ratingCounts[rating] += 1
            ratingSum += rating
            rated += 1
        }
        let averageRating = rated > 0 ? Double(ratingSum) / Double(rated) : nil

        func proofs(_ minutes: (BakeHistoryFacts) -> Int?) -> [ProofPoint] {
            completed.enumerated().compactMap { index, entry in
                guard let temperature = entry.facts.roomTemperature,
                      let minutes = minutes(entry.facts), minutes > 0 else { return nil }
                return ProofPoint(id: index, recipeName: entry.recipeName, date: entry.date,
                                  temperature: temperature, minutes: minutes)
            }
        }

        var outcomeCounts: [String: Int] = [:]
        for entry in completed {
            for keyword in BakeHistoryFacts.keywords(in: entry.facts.outcome) {
                outcomeCounts[keyword, default: 0] += 1
            }
        }
        let outcomes = outcomeCounts.map { OutcomeCount(keyword: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.keyword) > ($1.count, $0.keyword) }

        return BakeStatistics(total: total, thisYear: thisYear, firstDate: firstDate, perMonth: perMonth,
                              months: months, recipes: recipes, ratingCounts: ratingCounts,
                              averageRating: averageRating,
                              finalProofs: proofs(\.finalProofMinutes), bulkProofs: proofs(\.bulkProofMinutes),
                              outcomes: outcomes)
    }
}
