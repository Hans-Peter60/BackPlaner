//
//  KitchenYearbookTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("A year of cooking, summed up")
struct KitchenYearbookTests {

    private let calendar = Calendar(identifier: .gregorian)

    private func run(_ id: String, dish: String, day: Int, month: Int, year: Int = 2026, seconds: Int = 1_800,
                     planned: Int = 30, rating: Int? = nil, photo: Bool = false, relaxed: Bool = false,
                     manual: Bool = false) -> KitchenCookRun {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 18))!
        var run = manual
            ? KitchenCookRun.manualEntry(dishID: dish, dishName: dish, date: date)
            : KitchenCookRun(id: id, dishID: dish, dishName: dish, startedAt: date, totalSeconds: seconds,
                             plannedMinutes: planned, steps: [], totalSteps: nil)
        run.rating = rating
        if photo { run.photoFileName = id + ".jpg" }
        if relaxed { run.relaxed = true }
        return run
    }

    @Test("Figures, months, favourites, lessons and the cover come from the year's runs only")
    func compute() {
        let runs = [
            run("a", dish: "Pasta", day: 3, month: 1, seconds: 3_000, planned: 40, rating: 4, photo: true),
            run("b", dish: "Pasta", day: 10, month: 1, seconds: 2_400, planned: 40, rating: 5, photo: true),
            run("c", dish: "Curry", day: 5, month: 3, seconds: 2_100, planned: 30, rating: 3),
            run("d", dish: "Curry", day: 5, month: 3, seconds: 1_500, planned: 30, relaxed: true),
            run("e", dish: "Suppe", day: 1, month: 6, manual: true),
            run("z", dish: "Pasta", day: 2, month: 2, year: 2025, seconds: 4_000, planned: 40, rating: 5, photo: true),
        ]
        let now = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!
        let book = KitchenYearbook.compute(year: 2026, runs: runs, now: now, calendar: calendar)
        #expect(book.sessions == 5)
        #expect(book.cookingDays == 4)
        #expect(book.dishes == 3)
        #expect(book.hoursOnTheClock == 2.5)
        #expect(book.averageRating == 4)
        #expect(book.timedRuns == 3)
        #expect(book.withinPlan == 1)
        #expect(book.relaxedRuns == 1)
        #expect(book.longestSession?.name == "Pasta" && book.longestSession?.minutes == 50)
        #expect(book.monthCounts == [2, 0, 2, 0, 0, 1, 0, 0, 0, 0, 0, 0])
        #expect(book.months.map { $0.runs.count } == [2, 2, 1])
        #expect(book.favourites.map(\.name) == ["Curry", "Pasta", "Suppe"])
        let pasta = book.favourites.first { $0.name == "Pasta" }
        #expect(pasta?.averageRating == 4.5 && pasta?.photoRunID == "b" && pasta?.bestMinutes == 40)
        #expect(book.lessons == [KitchenYearbook.Lesson(dishID: "Pasta", name: "Pasta", firstMinutes: 50, latestMinutes: 40)])
        #expect(book.coverPhotoRunID == "b")
        #expect(KitchenYearbook.years(of: runs, now: now, calendar: calendar) == [2026, 2025])
        #expect(KitchenYearbook.compute(year: 2024, runs: runs, now: now, calendar: calendar).isEmpty)
    }
}
