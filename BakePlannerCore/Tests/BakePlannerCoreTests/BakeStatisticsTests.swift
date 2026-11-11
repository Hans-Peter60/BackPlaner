//
//  BakeStatisticsTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("What the bake history adds up to")
struct BakeStatisticsTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func entry(_ name: String, _ date: Date, rating: Int? = nil, room: Double? = nil,
                       final: Int? = nil, bulk: Int? = nil, outcome: String = "") -> BakeStatistics.Entry {
        BakeStatistics.Entry(recipeName: name, date: date,
                             facts: BakeHistoryFacts(roomTemperature: room, bulkProofMinutes: bulk,
                                                     finalProofMinutes: final, outcome: outcome, rating: rating))
    }

    private var now: Date { day(2026, 11, 11) }

    private var entries: [BakeStatistics.Entry] {
        [
            entry("Landbrot", day(2025, 12, 20), rating: 4, room: 21, final: 60, outcome: "offen, guter Ofentrieb"),
            entry("Landbrot", day(2026, 1, 10), rating: 5, room: 24, final: 45, bulk: 120, outcome: "offen"),
            entry("Landbrot", day(2026, 3, 2)),
            entry("Baguette", day(2026, 3, 15), rating: 3, room: 19, final: 90, outcome: "dicht"),
            entry("Baguette", day(2026, 11, 1), rating: 4),
            entry("Brioche", day(2026, 11, 10), rating: 4, room: 22, final: 0),
            // Planned for tomorrow: not a bake yet.
            entry("Landbrot", day(2026, 11, 12), rating: 5),
        ]
    }

    @Test("Only bakes up to now count; this year and the first bake are read off them")
    func totals() {
        let statistics = BakeStatistics.compute(entries: entries, now: now, calendar: calendar)
        #expect(statistics.total == 6)
        #expect(statistics.thisYear == 5)
        #expect(statistics.firstDate == day(2025, 12, 20))
        // 12 months from December 2025 to November 2026: 6 / 12.
        #expect(abs(statistics.perMonth - 0.5) < 0.001)
        #expect(!statistics.isEmpty)
    }

    @Test("Twelve months, oldest first, quiet months at zero")
    func months() {
        let statistics = BakeStatistics.compute(entries: entries, now: now, calendar: calendar)
        #expect(statistics.months.count == 12)
        #expect(statistics.months.first?.month == day(2025, 12, 1).addingTimeInterval(-12 * 3600))
        #expect(statistics.months.map(\.count) == [1, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 2])
    }

    @Test("Recipes are ranked by bakes, with the mean of their stars")
    func recipes() {
        let statistics = BakeStatistics.compute(entries: entries, now: now, calendar: calendar)
        #expect(statistics.recipes.map(\.name) == ["Landbrot", "Baguette", "Brioche"])
        #expect(statistics.recipes.map(\.count) == [3, 2, 1])
        #expect(statistics.recipes[0].averageRating == 4.5)
        #expect(statistics.recipes[1].averageRating == 3.5)
        #expect(statistics.recipes[0].lastDate == day(2026, 3, 2))
    }

    @Test("Stars are counted one to five, with their mean")
    func ratings() {
        let statistics = BakeStatistics.compute(entries: entries, now: now, calendar: calendar)
        #expect(statistics.ratingCounts == [0, 0, 0, 1, 3, 1])
        #expect(statistics.averageRating == 4)
    }

    @Test("A proof point needs a room temperature and a proof longer than zero")
    func proofs() {
        let statistics = BakeStatistics.compute(entries: entries, now: now, calendar: calendar)
        #expect(statistics.finalProofs.map(\.minutes) == [60, 45, 90])
        #expect(statistics.finalProofs.map(\.temperature) == [21, 24, 19])
        #expect(statistics.bulkProofs.map(\.minutes) == [120])
    }

    @Test("The outcome words are counted across bakes")
    func outcomes() {
        let statistics = BakeStatistics.compute(entries: entries, now: now, calendar: calendar)
        #expect(statistics.outcomes.map(\.keyword) == ["offen", "dicht", "guter Ofentrieb"])
        #expect(statistics.outcomes.map(\.count) == [2, 1, 1])
    }

    @Test("Without a completed bake everything is empty")
    func empty() {
        let statistics = BakeStatistics.compute(entries: [entry("Brot", day(2026, 12, 1))], now: now, calendar: calendar)
        #expect(statistics.isEmpty)
        #expect(statistics.months.count == 12)
        #expect(statistics.perMonth == 0)
        #expect(statistics.averageRating == nil)
    }
}
