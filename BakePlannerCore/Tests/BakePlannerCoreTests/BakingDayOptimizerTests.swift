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

    @Test("Same temperature, one oven: the two bakes share it; the second only moves a quarter hour so the hands are free")
    func sharedOven() {
        let result = schedule([bread("Weizen", bakeMinutes: 60), bread("Roggen", bakeMinutes: 60)], ovens: 1)
        #expect(Set(result.placements.map(\.finish)) == [date(14, 12), date(14, 11, 45)])
        #expect(result.placements.allSatisfy { !$0.overlapsWork && !$0.conflictsWithOvens })
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
        // A second bread before a 7:00 bread would knead at night; the search takes the latest finish
        // at which kneading and shaping are still done by the end of the day — the bake itself may run late.
        let pair = schedule([bread("Roggen", bakeMinutes: 60), bread("Weizen", bakeMinutes: 40, temperature: 230)], ovens: 1, finish: date(14, 7))
        let wheat = try #require(pair.placements.first { $0.id == "Weizen" })
        #expect(!BakingDayOptimizer.hasNightWork(wheat.plan, dayStart: 6, dayEnd: 22))
        #expect(wheat.finish >= date(13, 23) && wheat.finish <= date(13, 23, 45))
        // The first bread takes the wished time; with the oven blocked all day and night, the second cannot fit.
        let blocked = (0..<26).map { hour in
            BakeWindow(recipeName: "Dauerbrand \(hour)", start: date(13, 12).addingTimeInterval(Double(hour) * 3_600),
                       end: date(13, 13).addingTimeInterval(Double(hour) * 3_600), temperature: 180)
        }
        let jammed = schedule([bread("Weizen", bakeMinutes: 40)], ovens: 1, existing: blocked)
        #expect(jammed.placements.first?.conflictsWithOvens == true)
        #expect(!jammed.isClean(now: date(13, 8)))
    }

    @Test("A finish that would have to start in the past is never chosen for a pushed bread")
    func noPastStarts() throws {
        // Two breads, one oven, different temperatures, wished finish in four and a half hours:
        // the second cannot fit before the first without starting in the past — a conflict at the wished time.
        let result = schedule([bread("Weizen", bakeMinutes: 40, temperature: 230), bread("Roggen", bakeMinutes: 60)],
                              ovens: 1, finish: date(13, 12, 30))
        let wheat = try #require(result.placements.first { $0.id == "Weizen" })
        #expect(wheat.finish == date(13, 12, 30) && wheat.conflictsWithOvens)
        #expect(!wheat.startsInThePast(now: date(13, 8)))
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

@Suite("Bake windows: one oven only at the same temperature throughout the overlap")
struct BakeWindowSharingTests {

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: hour, minute: minute))!
    }

    @Test("Same temperature throughout: shared; a turn-down while the other still wants the heat: not shared")
    func profiles() {
        let steady = BakeWindow(recipeName: "A", start: date(11), end: date(12), temperature: 250)
        let other = BakeWindow(recipeName: "B", start: date(11, 20), end: date(12), temperature: 250)
        #expect(steady.sharesOven(with: other))

        let falling = BakeWindow(recipeName: "A", start: date(11), end: date(12), temperature: 250,
                                 temperatureChanges: [.init(at: date(11, 10), celsius: 220)])
        #expect(!falling.sharesOven(with: other))
        #expect(!other.sharesOven(with: falling))

        // Both fall to 220 at the same minute: shared.
        let fallingToo = BakeWindow(recipeName: "B", start: date(11), end: date(12), temperature: 250,
                                    temperatureChanges: [.init(at: date(11, 10), celsius: 220)])
        #expect(falling.sharesOven(with: fallingToo))

        // The second loaf goes in once the first is already at 220, wanting 220: shared.
        let lower = BakeWindow(recipeName: "C", start: date(11, 30), end: date(12), temperature: 220)
        #expect(falling.sharesOven(with: lower))
        #expect(!steady.sharesOven(with: lower))

        // Unknown temperature never shares.
        let unknown = BakeWindow(recipeName: "D", start: date(11), end: date(12))
        #expect(!steady.sharesOven(with: unknown))
    }

    @Test("A plan's window carries its turn-down; the validator reads it back from the planned steps")
    func fromPlan() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let steps = [
            PlanStep(instruction: "Teig kneten", step: 1, startTime: 0, duration: 15),
            PlanStep(instruction: "Stückgare", step: 2, startTime: 15, duration: 60),
            PlanStep(instruction: "Bei 250 °C fallend auf 220 °C 50 Minuten backen", step: 3, startTime: 75, duration: 50),
        ]
        let plan = BakePlan(recipeName: "Kruste", steps: steps, prepTime: 125, anchor: .startsAt, date: date(9),
                            languageCode: "de", preheatTime: 30, calendar: calendar)
        let window = try #require(plan.bakeWindow)
        #expect(window.temperature == 250)
        #expect(window.temperatureChanges == [.init(at: date(10, 25), celsius: 220)])
        #expect(window.temperature(at: date(10, 30)) == 220)

        let fromSteps = try #require(BakePlanValidator.bakeWindow(recipeName: "Kruste", steps: plan.plannedSteps))
        #expect(fromSteps.temperatureChanges == window.temperatureChanges)
    }
}

@Suite("Baking day: the hands are needed once at a time")
struct BakingDayWorkTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func bread(_ name: String, temperature: Int) -> BakingDayCandidate {
        let steps = [
            RecipeExportInstruction(instruction: "Teig kneten", step: 1, duration: 15, startTime: 0, bakeFlag: false),
            RecipeExportInstruction(instruction: "Stockgare", step: 2, duration: 120, startTime: 15, bakeFlag: false),
            RecipeExportInstruction(instruction: "Formen", step: 3, duration: 15, startTime: 135, bakeFlag: false),
            RecipeExportInstruction(instruction: "Stückgare", step: 4, duration: 60, startTime: 150, bakeFlag: false),
            RecipeExportInstruction(instruction: "Brot bei \(temperature) °C backen", step: 5, duration: 45, startTime: 210, bakeFlag: false),
        ]
        return BakingDayCandidate(id: name, recipe: RecipeExportData(name: name, summary: "", prepTime: 255, totalWeight: 1_000, tags: [],
                                                                     rating: 0, recurrenceIntervalDays: 0, components: [], instructions: steps))
    }

    @Test("Two ovens, two identical schedules: the second bread moves so that kneading and shaping do not coincide")
    func handsFree() throws {
        let result = BakingDayOptimizer.schedule([bread("A", temperature: 250), bread("B", temperature: 230)],
                                                 finishBy: date(14, 12), now: date(13, 8), ovenCount: 2, bakePause: 15,
                                                 dayStart: 6, dayEnd: 22, existingWindows: [], preheatTime: 30, calendar: calendar)
        let a = try #require(result.placements.first { $0.id == "A" })
        let b = try #require(result.placements.first { $0.id == "B" })
        #expect([a.finish, b.finish].contains(date(14, 12)))
        #expect(a.finish != b.finish)
        #expect(!a.overlapsWork && !b.overlapsWork)
        // A step already scheduled blocks the hands as well.
        let busy = [DateInterval(start: date(14, 7, 45), duration: 15 * 60)]
        let shifted = BakingDayOptimizer.schedule([bread("A", temperature: 250)], finishBy: date(14, 12), now: date(13, 8),
                                                  ovenCount: 1, bakePause: 15, dayStart: 6, dayEnd: 22,
                                                  existingWindows: [], existingWork: busy, preheatTime: 30, calendar: calendar)
        let single = try #require(shifted.placements.first)
        #expect(single.finish < date(14, 12) && !single.overlapsWork)
    }

    @Test("A bread that sleeps through the night is not thrown back a day: only hands-on work at night counts")
    func overnightStaysNear() throws {
        func overnight(_ name: String, temperature: Int) -> BakingDayCandidate {
            let steps = [
                RecipeExportInstruction(instruction: "Vorteig ansetzen", step: 1, duration: 10, startTime: 0, bakeFlag: false),
                RecipeExportInstruction(instruction: "Vorteig reifen lassen", step: 2, duration: 720, startTime: 10, bakeFlag: false),
                RecipeExportInstruction(instruction: "Teig kneten", step: 3, duration: 15, startTime: 730, bakeFlag: false),
                RecipeExportInstruction(instruction: "Stockgare", step: 4, duration: 120, startTime: 745, bakeFlag: false),
                RecipeExportInstruction(instruction: "Formen", step: 5, duration: 15, startTime: 865, bakeFlag: false),
                RecipeExportInstruction(instruction: "Stückgare", step: 6, duration: 60, startTime: 880, bakeFlag: false),
                RecipeExportInstruction(instruction: "Bei \(temperature) °C backen", step: 7, duration: 30, startTime: 940, bakeFlag: false),
            ]
            return BakingDayCandidate(id: name, recipe: RecipeExportData(name: name, summary: "", prepTime: 970, totalWeight: 1_000, tags: [],
                                                                         rating: 0, recurrenceIntervalDays: 0, components: [], instructions: steps))
        }
        // Two ovens, identical timing: the second only steps aside for the hands, a quarter hour.
        let result = BakingDayOptimizer.schedule([overnight("A", temperature: 250), overnight("B", temperature: 230)],
                                                 finishBy: date(14, 12), now: date(13, 8), ovenCount: 2, bakePause: 10,
                                                 dayStart: 6, dayEnd: 22, existingWindows: [], preheatTime: 30, calendar: calendar)
        let finishes = result.placements.map(\.finish).sorted()
        #expect(finishes == [date(14, 11, 45), date(14, 12)])
        #expect(result.placements.allSatisfy { !$0.overlapsWork })
    }

    @Test("Work intervals: kneading and shaping count, rests and oven steps do not, markers take five minutes")
    func intervals() throws {
        let at = date(14, 9)
        let kneading = try #require(BakingDayOptimizer.workInterval(instruction: "Teig kneten", duration: 15, date: at))
        #expect(kneading.start == at && kneading.duration == TimeInterval(900))
        let folding = try #require(BakingDayOptimizer.workInterval(instruction: "Dehnen und falten", duration: 0, date: at))
        #expect(folding.duration == TimeInterval(300))
        #expect(BakingDayOptimizer.workInterval(instruction: "Stockgare bei 24 °C", duration: 120, date: at) == nil)
        // Mixing that ripens for hours, or a rest with folds in it: the hands only at the start.
        #expect(BakingDayOptimizer.workInterval(instruction: "Mehl und Wasser mischen und 12 Stunden stehen lassen", duration: 720, date: at)?.duration == TimeInterval(1_800))
        #expect(BakingDayOptimizer.workInterval(instruction: "2,5 Stunden ruhen lassen, dabei dehnen und falten", duration: 150, date: at)?.duration == TimeInterval(1_800))
        #expect(BakingDayOptimizer.workInterval(instruction: "Teigruhe bei ca. 20 °C", duration: 45, date: at) == nil)
        #expect(BakingDayOptimizer.workInterval(instruction: "Backofen auf 250 °C vorheizen", duration: 30, date: at) == nil)
        #expect(BakingDayOptimizer.workInterval(instruction: "Über Nacht im Kühlschrank reifen lassen", duration: 720, date: at) == nil)
    }
}
