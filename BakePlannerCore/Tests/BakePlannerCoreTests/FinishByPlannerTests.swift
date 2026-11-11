import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Fertig bis: whether a recipe can still be made, and when it must start")
struct FinishByPlannerTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func step(_ text: String, _ number: Double, _ minutes: Int, start: Int = 0) -> RecipeExportInstruction {
        RecipeExportInstruction(instruction: text, step: number, duration: minutes, startTime: start, bakeFlag: false)
    }

    private func recipe(_ steps: [RecipeExportInstruction], prepTime: Int = 0) -> RecipeExportData {
        RecipeExportData(name: "Brot", summary: "", urlLink: "", prepTime: prepTime, totalWeight: 0, tags: [],
                         rating: 0, recurrenceIntervalDays: 0, image: nil, components: [], instructions: steps)
    }

    /// Knead at 0, rest 12 h, shape, proof 60, bake 45 — 14 h 15 in all,
    /// with the stored start times.
    private var overnight: RecipeExportData {
        recipe([
            step("Teig kneten", 1, 15, start: 0),
            step("Über Nacht im Kühlschrank reifen lassen", 2, 720, start: 15),
            step("Formen", 3, 15, start: 735),
            step("Stückgare", 4, 60, start: 750),
            step("Brot bei 250 °C backen", 5, 45, start: 810),
        ], prepTime: 855)
    }

    @Test("The start is the finish less the plan's length; preheating lies inside it")
    func startFromFinish() throws {
        let finish = date(12, 7, 30)
        let outcome = try #require(FinishByPlanner.outcome(for: overnight, finishBy: finish, now: date(11, 12),
                                                            dayStart: 6, dayEnd: 22, preheatTime: 30, calendar: calendar))
        #expect(outcome.start == date(11, 17, 15))
        #expect(outcome.totalMinutes == 855)
    }

    @Test("Too late: a start before now means the recipe cannot be made")
    func tooLate() {
        let finish = date(11, 20)
        #expect(FinishByPlanner.outcome(for: overnight, finishBy: finish, now: date(11, 12), calendar: calendar) == nil)
        // A short recipe still fits.
        let quick = recipe([step("Kneten", 1, 15, start: 0), step("Gehen lassen", 2, 60, start: 15), step("Backen", 3, 30, start: 75)])
        let outcome = FinishByPlanner.outcome(for: quick, finishBy: finish, now: date(11, 12), preheatTime: 20, calendar: calendar)
        #expect(outcome?.start == date(11, 18, 15))
        #expect(outcome?.totalMinutes == 105)
    }

    @Test("A bake right after the mixing: the oven goes on before the first step, and that is the start")
    func preheatBeforeFirstStep() throws {
        let flat = recipe([step("Teig anrühren", 1, 10, start: 0), step("Fladen bei 250 °C backen", 2, 30, start: 10)])
        let outcome = try #require(FinishByPlanner.outcome(for: flat, finishBy: date(11, 20), now: date(11, 12),
                                                            preheatTime: 30, calendar: calendar))
        #expect(outcome.start == date(11, 19))
        #expect(outcome.totalMinutes == 60)
    }

    @Test("Steps without start times follow one another; no timed steps, no outcome")
    func sequentialAndEmpty() {
        let untimed = recipe([step("Kneten", 1, 10), step("Gehen", 2, 50), step("Backen", 3, 30)])
        let outcome = FinishByPlanner.outcome(for: untimed, finishBy: date(11, 18), now: date(11, 12), preheatTime: 0, calendar: calendar)
        #expect(outcome?.start == date(11, 16, 30))
        #expect(FinishByPlanner.outcome(for: recipe([]), finishBy: date(11, 18), now: date(11, 12), calendar: calendar) == nil)
        #expect(FinishByPlanner.outcome(for: recipe([step("Kneten", 1, 0)]), finishBy: date(11, 18), now: date(11, 12), calendar: calendar) == nil)
    }

    @Test("A step that begins at night is flagged; one inside the day is not")
    func nightSteps() throws {
        // Finish at 7:30: shaping at 5:45 lies before a day start of 6.
        let early = try #require(FinishByPlanner.outcome(for: overnight, finishBy: date(12, 7, 30), now: date(11, 12),
                                                          dayStart: 6, dayEnd: 22, preheatTime: 30, calendar: calendar))
        #expect(early.hasNightSteps)
        // Finish at 9:30: everything from 19:15 to 9:30 that is a step start falls inside 6–22.
        let later = try #require(FinishByPlanner.outcome(for: overnight, finishBy: date(12, 9, 30), now: date(11, 12),
                                                          dayStart: 6, dayEnd: 22, preheatTime: 30, calendar: calendar))
        #expect(!later.hasNightSteps)
    }

    @Test("\"Für morgen früh\" aims at tomorrow half past seven, or half past a later day start")
    func morningFinish() {
        #expect(FinishByPlanner.morningFinish(after: date(11, 15), dayStart: 6, calendar: calendar) == date(12, 7, 30))
        #expect(FinishByPlanner.morningFinish(after: date(11, 23, 59), dayStart: 9, calendar: calendar) == date(12, 9, 30))
    }
}
