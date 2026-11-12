import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Baking day: several breads before one finish, the ovens respected")
struct BakingDayOptimizerTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func step(_ text: String, _ number: Double, _ minutes: Int, start: Int) -> RecipeExportInstruction {
        RecipeExportInstruction(instruction: text, step: number, duration: minutes, startTime: start, bakeFlag: false)
    }

    /// Knead, rest, shape, proof, bake `bakeMinutes` — about four hours.
    private func bread(_ name: String, bakeMinutes: Int, temperature: Int = 250) -> BakingDayCandidate {
        let steps = [
            step("Teig kneten", 1, 15, start: 0),
            step("Stockgare", 2, 120, start: 15),
            step("Formen", 3, 15, start: 135),
            step("Stückgare", 4, 60, start: 150),
            step("Brot bei \(temperature) °C backen", 5, bakeMinutes, start: 210),
        ]
        let recipe = RecipeExportData(name: name, summary: "", prepTime: 210 + bakeMinutes, totalWeight: 1_000, tags: [],
                                      rating: 0, recurrenceIntervalDays: 0, components: [], instructions: steps)
        return BakingDayCandidate(id: name, recipe: recipe)
    }

    private func schedule(_ candidates: [BakingDayCandidate], ovens: Int, pause: Int = 15,
                          existing: [BakeWindow] = [], finish: Date? = nil) -> BakingDaySchedule {
        BakingDayOptimizer.schedule(candidates, finishBy: finish ?? date(14, 12), now: date(13, 8),
                                    ovenCount: ovens, bakePause: pause, dayStart: 6, dayEnd: 22,
                                    existingWindows: existing, preheatTime: 30, calendar: calendar)
    }

    @Test("Two breads, one oven: the longer bake finishes at the wished time, the other before it, pause kept")
    func oneOven() throws {
        let result = schedule([bread("Weizen", bakeMinutes: 40, temperature: 230), bread("Roggen", bakeMinutes: 60)], ovens: 1)
        #expect(result.unplaced.isEmpty)
        let rye = try #require(result.placements.first { $0.id == "Roggen" })
        let wheat = try #require(result.placements.first { $0.id == "Weizen" })
        #expect(rye.finish == date(14, 12))
        // The wheat's bake must end 15 minutes before the rye's bake starts (11:00): latest quarter hour is 10:45.
        #expect(wheat.finish == date(14, 10, 45))
        #expect(!rye.conflictsWithOvens && !wheat.conflictsWithOvens)
        #expect(result.placements.map(\.id) == ["Weizen", "Roggen"])
        #expect(result.isClean(now: date(13, 8)))
    }

    @Test("Two ovens: both breads finish at the wished time")
    func twoOvens() {
        let result = schedule([bread("Weizen", bakeMinutes: 40, temperature: 230), bread("Roggen", bakeMinutes: 60)], ovens: 2)
        #expect(result.placements.allSatisfy { $0.finish == date(14, 12) })
    }

    @Test("Same temperature, one oven: the two bakes share it and both finish at the wished time")
    func sharedOven() {
        let result = schedule([bread("Weizen", bakeMinutes: 60), bread("Roggen", bakeMinutes: 60)], ovens: 1)
        #expect(result.placements.allSatisfy { $0.finish == date(14, 12) })
    }

    @Test("A bake already scheduled pushes the new bread earlier")
    func existingWindow() throws {
        let existing = [BakeWindow(recipeName: "Baguette", start: date(14, 11), end: date(14, 12), temperature: 230)]
        let result = schedule([bread("Roggen", bakeMinutes: 60)], ovens: 1, existing: existing)
        let rye = try #require(result.placements.first)
        #expect(rye.finish == date(14, 10, 45))
    }

    @Test("The wished time stays even with night steps; a pushed bread avoids them where it can; no fit within a day is a conflict")
    func nightAndConflict() throws {
        // A finish at 7:00 puts the kneading at 3:30 — the wished time is kept, the night is flagged.
        let early = schedule([bread("Roggen", bakeMinutes: 60)], ovens: 1, finish: date(14, 7))
        let rye = try #require(early.placements.first)
        #expect(rye.finish == date(14, 7))
        #expect(rye.hasNightSteps)
        // A second bread before a 7:00 bread would knead at night; the search prefers the evening before.
        let pair = schedule([bread("Roggen", bakeMinutes: 60), bread("Weizen", bakeMinutes: 40, temperature: 230)], ovens: 1, finish: date(14, 7))
        let wheat = try #require(pair.placements.first { $0.id == "Weizen" })
        #expect(!wheat.hasNightSteps)
        #expect(wheat.finish <= date(13, 22))
        // The first bread takes the wished time; with the oven blocked all day and night, the second cannot fit.
        let blocked = (0..<26).map { hour in
            BakeWindow(recipeName: "Dauerbrand \(hour)", start: date(13, 12).addingTimeInterval(Double(hour) * 3_600),
                       end: date(13, 13).addingTimeInterval(Double(hour) * 3_600), temperature: 180)
        }
        let jammed = schedule([bread("Weizen", bakeMinutes: 40)], ovens: 1, existing: blocked)
        #expect(jammed.placements.first?.conflictsWithOvens == true)
        #expect(!jammed.isClean(now: date(13, 8)))
    }

    @Test("A recipe without timed steps is not placed; a start before now is flagged")
    func unplacedAndPast() {
        let empty = BakingDayCandidate(id: "Leer", recipe: RecipeExportData(name: "Leer", summary: "", prepTime: 0, totalWeight: 0, tags: [],
                                                                               rating: 0, recurrenceIntervalDays: 0, components: [], instructions: []))
        let result = schedule([empty, bread("Roggen", bakeMinutes: 60)], ovens: 1, finish: date(13, 10))
        #expect(result.unplaced.map(\.id) == ["Leer"])
        #expect(result.placements.first?.startsInThePast(now: date(13, 8)) == true)
    }
}
