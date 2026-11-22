import Foundation
import Testing
@testable import BakePlannerCore

@Suite("CookPlanner: what the cooking history adds up to")
struct KitchenCookStatisticsTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 19))!
    }

    private func timed(_ dish: String, _ month: Int, _ day: Int, seconds: Int, planned: Int, rating: Int?) -> KitchenCookRun {
        var run = KitchenCookRun(dishID: dish, dishName: dish.capitalized, startedAt: date(month, day),
                                 totalSeconds: seconds, plannedMinutes: planned,
                                 steps: [KitchenCookRun.Step(taskID: "t", name: "t", component: "", plannedMinutes: planned,
                                                             plannedStart: 0, startedSecond: 0, doneSecond: seconds,
                                                             tickedByCook: true)], totalSteps: 1)
        run.rating = rating
        return run
    }

    @Test("A manual entry has no stopwatch and clamps its stars")
    func manual() {
        let entry = KitchenCookRun.manualEntry(dishID: "d", dishName: "Ente", date: date(11, 1), rating: 7, note: "  lecker ")
        #expect(entry.isManualEntry && entry.rating == 5 && entry.note == "lecker")
        #expect(!timed("ente", 11, 2, seconds: 600, planned: 10, rating: nil).isManualEntry)
        #expect(KitchenCookRun.manualEntry(dishID: "d", dishName: "Ente", date: date(11, 1), note: " ").note == nil)
    }

    @Test("Totals, stars, the plan and the dishes")
    func sums() {
        let runs = [
            timed("ente", 11, 2, seconds: 50 * 60, planned: 45, rating: 4),
            timed("ente", 10, 5, seconds: 40 * 60, planned: 45, rating: 5),
            timed("salat", 11, 10, seconds: 20 * 60, planned: 20, rating: 3),
            KitchenCookRun.manualEntry(dishID: "risotto", dishName: "Risotto", date: date(9, 1)),
        ]
        let statistics = KitchenCookStatistics(runs: runs, now: date(11, 20), calendar: calendar)
        #expect(statistics.total == 4 && statistics.dishCount == 3)
        #expect(statistics.averageRating == 4)
        #expect(statistics.timedRuns == 3 && statistics.averageMinutesOverPlan == 0)
        #expect(statistics.mostCooked.first?.dishID == "ente" && statistics.mostCooked.first?.count == 2)
        #expect(statistics.hitList.map(\.dishID) == ["ente", "salat"])
        #expect(statistics.hitList.first?.averageRating == 4.5)
        #expect(statistics.months.count == 12)
        #expect(statistics.months.last?.count == 2)
        #expect(statistics.months.suffix(3).map(\.count) == [1, 1, 2])
    }
}
