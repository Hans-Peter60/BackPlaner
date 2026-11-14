//
//  BakeYearbookTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("A year of baking, summed up for the yearbook")
struct BakeYearbookTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func bake(_ name: String, _ date: Date, rating: Int? = nil, room: Double? = nil, final: Int? = nil,
                      flour: String = "", outcome: String = "", photos: Int = 0, grams: Double = 500,
                      dough: Double = 850, minutes: Int = 600) -> BakeYearbook.Entry {
        BakeYearbook.Entry(recipeName: name, date: date,
                           facts: BakeHistoryFacts(roomTemperature: room, finalProofMinutes: final, flour: flour,
                                                   outcome: outcome, rating: rating),
                           photoCount: photos, photoKey: "\(name)-\(Int(date.timeIntervalSince1970))",
                           flourGrams: grams, doughGrams: dough, durationMinutes: minutes)
    }

    private var now: Date { day(2026, 11, 14) }

    private var entries: [BakeYearbook.Entry] {
        [
            bake("Landbrot", day(2025, 12, 20), rating: 4, photos: 1),
            bake("Landbrot", day(2026, 1, 10), rating: 5, room: 24, final: 50, flour: "Weizen 550", outcome: "offen", photos: 1),
            bake("Landbrot", day(2026, 1, 10), rating: 3, room: 22, final: 60, flour: "Weizen 550", photos: 0),
            bake("Baguette", day(2026, 3, 15), rating: 3, room: 19, final: 90, flour: "Weizen 550, T65", outcome: "dicht", photos: 2, minutes: 1_200),
            bake("Baguette", day(2026, 6, 1), rating: 4, room: 25, final: 40, flour: "T65", outcome: "offen, guter Ofentrieb"),
            bake("Brioche", day(2026, 11, 10), rating: 4, room: 23, final: 70, photos: 1, minutes: 300),
            bake("Landbrot", day(2026, 11, 20)),
        ]
    }

    @Test("Only the year's finished bakes count; days, kilograms, stars and the longest bread")
    func figures() {
        let book = BakeYearbook.compute(year: 2026, entries: entries, now: now, calendar: calendar)
        #expect(book.bakes == 5)
        #expect(book.bakingDays == 4)
        #expect(book.flourKilograms == 2.5)
        #expect(book.doughKilograms == 4.25)
        #expect(book.averageRating == 3.8)
        #expect(book.favouriteFlour == "Weizen 550")
        #expect(book.longestBake?.name == "Baguette" && book.longestBake?.minutes == 1_200)
        #expect(book.monthCounts == [2, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0])
        #expect(book.months.map { calendar.component(.month, from: $0.start) } == [1, 3, 6, 11])
        #expect(book.months[0].entries.count == 2)
    }

    @Test("Favourites by count, alphabetical on a tie; the best-rated photo as the cover")
    func favourites() {
        let book = BakeYearbook.compute(year: 2026, entries: entries, now: now, calendar: calendar)
        #expect(book.favourites.map(\.name) == ["Baguette", "Landbrot", "Brioche"])
        #expect(book.favourites[0].count == 2 && book.favourites[1].count == 2)
        #expect(book.favourites[1].averageRating == 4)
        #expect(book.favourites[1].photoKey == "Landbrot-\(Int(day(2026, 1, 10).timeIntervalSince1970))")
        #expect(book.favourites[0].averageFinalProofMinutes == 65)
        #expect(book.favourites[0].averageRoomTemperature == 22)
        // The five-star Landbrot of January has a photo: it is the cover.
        #expect(book.coverPhotoKey == book.favourites[1].photoKey)
        #expect(book.outcomes.first == BakeStatistics.OutcomeCount(keyword: "offen", count: 2))
    }

    @Test("Proof lessons group the room temperature in bands of three degrees and need two bakes")
    func proofLessons() {
        let book = BakeYearbook.compute(year: 2026, entries: entries, now: now, calendar: calendar)
        // 24 and 25 °C → band 24–26 with 50 and 40 minutes; 22 and 23 → 21–23 with 60 and 70; 19 alone.
        #expect(book.proofLessons == [
            BakeYearbook.ProofLesson(lowerTemperature: 21, upperTemperature: 23, medianFinalProofMinutes: 65, bakes: 2),
            BakeYearbook.ProofLesson(lowerTemperature: 24, upperTemperature: 26, medianFinalProofMinutes: 45, bakes: 2),
        ])
    }

    @Test("The starter's year: feedings, the longest pause, peaks by season")
    func starter() {
        let feedings = [
            BakeYearbook.Feeding(starterName: "Roggensauer", date: day(2026, 1, 3), peakMinutes: 600),
            BakeYearbook.Feeding(starterName: "Roggensauer", date: day(2026, 1, 8), peakMinutes: 540),
            BakeYearbook.Feeding(starterName: "Roggensauer", date: day(2026, 2, 20)),
            BakeYearbook.Feeding(starterName: "Roggensauer", date: day(2026, 7, 1), peakMinutes: 300),
            BakeYearbook.Feeding(starterName: "Weizensauer", date: day(2026, 7, 2), peakMinutes: 360),
            BakeYearbook.Feeding(starterName: "Weizensauer", date: day(2025, 7, 2), peakMinutes: 999),
        ]
        let book = BakeYearbook.compute(year: 2026, entries: entries, feedings: feedings, now: now, calendar: calendar)
        let starter = book.starter
        #expect(starter?.feedings == 5)
        #expect(starter?.starters == 2)
        #expect(starter?.longestPauseDays == 131)
        #expect(starter?.averagePeakMinutesWinter == 570)
        #expect(starter?.averagePeakMinutesSummer == 330)
        #expect(BakeYearbook.compute(year: 2026, entries: entries, now: now, calendar: calendar).starter == nil)
    }

    @Test("A year without bakes is empty; the years list names only finished years")
    func emptyAndYears() {
        let book = BakeYearbook.compute(year: 2024, entries: entries, now: now, calendar: calendar)
        #expect(book.isEmpty && book.months.isEmpty && book.favourites.isEmpty && book.coverPhotoKey == nil)
        #expect(BakeYearbook.years(of: entries.map(\.date), now: now, calendar: calendar) == [2026, 2025])
    }
}
