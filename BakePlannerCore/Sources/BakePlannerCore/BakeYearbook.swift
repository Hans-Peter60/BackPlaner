//
//  BakeYearbook.swift
//  BakePlannerCore
//
//  A year of baking, summed up for the yearbook PDF: the figures of the
//  year, the bakes month by month, the recipes baked most, what the facts
//  taught, and the starter's year. The sums live here so both apps and the
//  tests share them; the drawing is each app's.
//

import Foundation

public struct BakeYearbook: Equatable {

    /// One completed bake of the year, with what the yearbook shows of it.
    public struct Entry: Equatable {
        public let recipeName: String
        public let date: Date
        public let facts: BakeHistoryFacts
        public let comment: String
        /// How many photos the bake has; the apps hand the pictures to the
        /// renderer separately, keyed by `photoKey`.
        public let photoCount: Int
        /// The key the renderer finds the bake's first photo under.
        public let photoKey: String
        /// Grams of flour the recipe's dough takes, at the recipe's amount.
        public let flourGrams: Double
        /// The recipe's dough weight at its amount.
        public let doughGrams: Double
        /// Minutes from the first to the last step of the recipe.
        public let durationMinutes: Int

        public init(recipeName: String, date: Date, facts: BakeHistoryFacts = BakeHistoryFacts(), comment: String = "",
                    photoCount: Int = 0, photoKey: String = "", flourGrams: Double = 0, doughGrams: Double = 0,
                    durationMinutes: Int = 0) {
            self.recipeName = recipeName
            self.date = date
            self.facts = facts
            self.comment = comment
            self.photoCount = photoCount
            self.photoKey = photoKey
            self.flourGrams = flourGrams
            self.doughGrams = doughGrams
            self.durationMinutes = durationMinutes
        }
    }

    /// One feeding of a starter in the year.
    public struct Feeding: Equatable, Sendable {
        public let starterName: String
        public let date: Date
        public let peakMinutes: Int?

        public init(starterName: String, date: Date, peakMinutes: Int? = nil) {
            self.starterName = starterName
            self.date = date
            self.peakMinutes = peakMinutes
        }
    }

    public struct Month: Equatable {
        /// The first day of the month.
        public let start: Date
        public let entries: [Entry]
    }

    public struct Favourite: Equatable, Sendable {
        public let name: String
        public let count: Int
        public let averageRating: Double?
        /// The photo key of the best-rated bake with a photo, if any.
        public let photoKey: String?
        public let averageRoomTemperature: Double?
        public let averageFinalProofMinutes: Int?
    }

    /// What the final proofs taught at a room temperature: the middle
    /// value over the bakes measured in that band.
    public struct ProofLesson: Equatable, Sendable {
        public let lowerTemperature: Int
        public let upperTemperature: Int
        public let medianFinalProofMinutes: Int
        public let bakes: Int
    }

    public struct StarterYear: Equatable, Sendable {
        public let feedings: Int
        public let starters: Int
        /// The longest gap between two feedings of one starter, in days.
        public let longestPauseDays: Int?
        /// Average peak time in the cold and the warm half of the year.
        public let averagePeakMinutesWinter: Int?
        public let averagePeakMinutesSummer: Int?
    }

    public static let favouriteCount = 5
    public static let outcomeCount = 8

    public let year: Int
    public let bakes: Int
    /// Distinct days with a bake.
    public let bakingDays: Int
    public let flourKilograms: Double
    public let doughKilograms: Double
    public let averageRating: Double?
    /// The most frequent flour named in the facts, if any was.
    public let favouriteFlour: String?
    public let longestBake: (name: String, minutes: Int)?
    /// Twelve counts, January first.
    public let monthCounts: [Int]
    /// Only the months with bakes, January first.
    public let months: [Month]
    public let favourites: [Favourite]
    public let outcomes: [BakeStatistics.OutcomeCount]
    public let proofLessons: [ProofLesson]
    public let starter: StarterYear?
    /// The photo key for the cover: the best-rated bake with a photo, else
    /// the most-baked recipe's first photo, else the first photo at all.
    public let coverPhotoKey: String?

    public var isEmpty: Bool { bakes == 0 }

    public static func == (lhs: BakeYearbook, rhs: BakeYearbook) -> Bool {
        lhs.year == rhs.year && lhs.bakes == rhs.bakes && lhs.monthCounts == rhs.monthCounts
            && lhs.favourites == rhs.favourites && lhs.coverPhotoKey == rhs.coverPhotoKey
    }

    /// The years that have a completed bake, newest first.
    public static func years(of dates: [Date], now: Date = Date(), calendar: Calendar = .current) -> [Int] {
        Array(Set(dates.filter { $0 <= now }.map { calendar.component(.year, from: $0) })).sorted(by: >)
    }

    public static func compute(year: Int, entries: [Entry], feedings: [Feeding] = [], now: Date = Date(),
                               calendar: Calendar = .current) -> BakeYearbook {
        let bakesOfYear = entries
            .filter { $0.date <= now && calendar.component(.year, from: $0.date) == year }
            .sorted { $0.date < $1.date }

        let days = Set(bakesOfYear.map { calendar.startOfDay(for: $0.date) })
        let flour = bakesOfYear.reduce(0.0) { $0 + $1.flourGrams } / 1_000
        let dough = bakesOfYear.reduce(0.0) { $0 + $1.doughGrams } / 1_000

        let ratings = bakesOfYear.compactMap(\.facts.rating).filter { (1...BakeHistoryFacts.maximumRating).contains($0) }
        let averageRating = ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)

        var flourCounts: [String: Int] = [:]
        for entry in bakesOfYear {
            for name in BakeHistoryFacts.keywords(in: entry.facts.flour) {
                flourCounts[name, default: 0] += 1
            }
        }
        let favouriteFlour = flourCounts.max { a, b in (a.value, b.key) < (b.value, a.key) }?.key

        let longest = bakesOfYear.filter { $0.durationMinutes > 0 }.max { a, b in
            (a.durationMinutes, b.recipeName) < (b.durationMinutes, a.recipeName)
        }

        var monthCounts = Array(repeating: 0, count: 12)
        var byMonth: [Int: [Entry]] = [:]
        for entry in bakesOfYear {
            let month = calendar.component(.month, from: entry.date)
            monthCounts[month - 1] += 1
            byMonth[month, default: []].append(entry)
        }
        let months: [Month] = (1...12).compactMap { month in
            guard let entries = byMonth[month],
                  let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
            return Month(start: start, entries: entries)
        }

        var byRecipe: [String: [Entry]] = [:]
        for entry in bakesOfYear {
            byRecipe[entry.recipeName, default: []].append(entry)
        }
        let favourites: [Favourite] = byRecipe
            .map { name, entries in
                let stars = entries.compactMap(\.facts.rating)
                let rooms = entries.compactMap(\.facts.roomTemperature)
                let proofs = entries.compactMap(\.facts.finalProofMinutes).filter { $0 > 0 }
                return Favourite(
                    name: name,
                    count: entries.count,
                    averageRating: stars.isEmpty ? nil : Double(stars.reduce(0, +)) / Double(stars.count),
                    photoKey: bestPhoto(of: entries),
                    averageRoomTemperature: rooms.isEmpty ? nil : rooms.reduce(0, +) / Double(rooms.count),
                    averageFinalProofMinutes: proofs.isEmpty ? nil : proofs.reduce(0, +) / proofs.count)
            }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
            .prefix(favouriteCount)
            .map { $0 }

        var outcomeCounts: [String: Int] = [:]
        for entry in bakesOfYear {
            for keyword in BakeHistoryFacts.keywords(in: entry.facts.outcome) {
                outcomeCounts[keyword, default: 0] += 1
            }
        }
        let outcomes = outcomeCounts.map { BakeStatistics.OutcomeCount(keyword: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.keyword) > ($1.count, $0.keyword) }
            .prefix(outcomeCount)
            .map { $0 }

        let cover = bestPhoto(of: bakesOfYear)
            ?? favourites.first?.photoKey
            ?? bakesOfYear.first { $0.photoCount > 0 }?.photoKey

        return BakeYearbook(year: year, bakes: bakesOfYear.count, bakingDays: days.count,
                            flourKilograms: flour, doughKilograms: dough, averageRating: averageRating,
                            favouriteFlour: favouriteFlour,
                            longestBake: longest.map { ($0.recipeName, $0.durationMinutes) },
                            monthCounts: monthCounts, months: months, favourites: favourites, outcomes: outcomes,
                            proofLessons: proofLessons(of: bakesOfYear),
                            starter: starterYear(of: feedings, year: year, now: now, calendar: calendar),
                            coverPhotoKey: cover)
    }

    /// The photo of the best-rated bake; unrated bakes count as nothing,
    /// the earlier bake wins a tie.
    static func bestPhoto(of entries: [Entry]) -> String? {
        entries.filter { $0.photoCount > 0 }
            .max { a, b in (a.facts.rating ?? 0, b.date) < (b.facts.rating ?? 0, a.date) }?
            .photoKey
    }

    /// The final proofs grouped by room temperature in bands of three
    /// degrees (18–20, 21–23, 24–26 …); a band needs two measured bakes.
    static func proofLessons(of entries: [Entry]) -> [ProofLesson] {
        var bands: [Int: [Int]] = [:]
        for entry in entries {
            guard let temperature = entry.facts.roomTemperature,
                  let minutes = entry.facts.finalProofMinutes, minutes > 0 else { continue }
            let lower = Int((temperature / 3).rounded(.down)) * 3
            bands[lower, default: []].append(minutes)
        }
        return bands
            .filter { $0.value.count >= 2 }
            .map { lower, minutes in
                let sorted = minutes.sorted()
                let median = sorted.count % 2 == 1
                    ? sorted[sorted.count / 2]
                    : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
                return ProofLesson(lowerTemperature: lower, upperTemperature: lower + 2,
                                   medianFinalProofMinutes: median, bakes: sorted.count)
            }
            .sorted { $0.lowerTemperature < $1.lowerTemperature }
    }

    static func starterYear(of feedings: [Feeding], year: Int, now: Date, calendar: Calendar) -> StarterYear? {
        let ofYear = feedings
            .filter { $0.date <= now && calendar.component(.year, from: $0.date) == year }
            .sorted { $0.date < $1.date }
        guard !ofYear.isEmpty else { return nil }

        var longestPause: Int?
        for (_, dates) in Dictionary(grouping: ofYear, by: \.starterName).mapValues({ $0.map(\.date) }) {
            for (earlier, later) in zip(dates, dates.dropFirst()) {
                let days = calendar.dateComponents([.day], from: earlier, to: later).day ?? 0
                longestPause = max(longestPause ?? 0, days)
            }
        }

        func averagePeak(_ months: ClosedRange<Int>) -> Int? {
            let peaks = ofYear.filter { months.contains(calendar.component(.month, from: $0.date)) }
                .compactMap(\.peakMinutes).filter { $0 > 0 }
            return peaks.isEmpty ? nil : peaks.reduce(0, +) / peaks.count
        }
        // Winter: November to March; summer: May to September.
        let winter = ofYear.filter { [11, 12, 1, 2, 3].contains(calendar.component(.month, from: $0.date)) }
            .compactMap(\.peakMinutes).filter { $0 > 0 }
        return StarterYear(feedings: ofYear.count,
                           starters: Set(ofYear.map(\.starterName)).count,
                           longestPauseDays: longestPause,
                           averagePeakMinutesWinter: winter.isEmpty ? nil : winter.reduce(0, +) / winter.count,
                           averagePeakMinutesSummer: averagePeak(5...9))
    }
}
