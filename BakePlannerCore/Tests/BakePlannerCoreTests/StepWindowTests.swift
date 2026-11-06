//
//  StepWindowTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Steps with a duration window")
struct StepWindowTests {

    // MARK: The window itself

    @Test("A window needs both bounds and a width")
    func bounds() {
        #expect(DurationWindow.range(minimum: 45, maximum: 90) == 45...90)
        #expect(DurationWindow.range(minimum: 60, maximum: 60) == nil)
        #expect(DurationWindow.range(minimum: nil, maximum: 90) == nil)
        #expect(DurationWindow.range(minimum: -5, maximum: 90) == nil)

        var instruction = RecipeExportInstruction(instruction: "Ruhen", step: 1, duration: 60, startTime: 0, bakeFlag: false)
        instruction.durationWindow = 45...90
        #expect(instruction.minDuration == 45 && instruction.maxDuration == 90)
        instruction.durationWindow = nil
        #expect(instruction.minDuration == nil && instruction.maxDuration == nil)
    }

    @Test("The wording gives a window in German, English and French; the oven's time does not count")
    func parsed() {
        #expect(DurationWindow.parse("Über Nacht 12–18 Stunden im Kühlschrank reifen lassen.") == 720...1080)
        #expect(DurationWindow.parse("30 bis 60 Minuten gehen lassen") == 30...60)
        #expect(DurationWindow.parse("8-12 Std. bei 9 °C lagern") == 480...720)
        #expect(DurationWindow.parse("Let the dough rise for 1 to 1.5 hours.") == 60...90)
        #expect(DurationWindow.parse("Laisser pousser 1 à 2 heures.") == 60...120)
        #expect(DurationWindow.parse("Bei 250 °C 20–25 Minuten backen") == nil)
        #expect(DurationWindow.parse("Backofen 30-45 Minuten vorheizen") == nil)
        #expect(DurationWindow.parse("Bei 24–26 °C 3 Stunden gehen lassen") == nil)
        #expect(DurationWindow.parse("Nach 30 und 60 Minuten falten") == nil)
        #expect(DurationWindow.parse("2 Stunden gehen lassen") == nil)
    }

    @Test("A stored window wins; the wording's counts only around the step's own duration")
    func effective() {
        #expect(DurationWindow.effective(stored: 100...200, instruction: "12–18 Stunden", duration: 900) == 100...200)
        #expect(DurationWindow.effective(stored: nil, instruction: "12–18 Stunden reifen", duration: 900) == 720...1080)
        #expect(DurationWindow.effective(stored: nil, instruction: "12–18 Stunden reifen", duration: 1200) == nil)
        #expect(DurationWindow.effective(stored: nil, instruction: "12–18 Stunden reifen", duration: 0) == nil)
    }

    @Test("A window reads as the tables show durations")
    func text() {
        #expect(DurationWindow.text(720...1080) == "12h 00m – 18h 00m")
        #expect(DurationWindow.text(30...60) == "30m – 1h 00m")
    }

    // MARK: The advisor

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    /// Friday 9 October 2026, or Saturday the 10th with `day: 10`.
    private func time(_ hour: Int, _ minute: Int = 0, day: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// A sourdough loaf: the starter may ripen 10 to 14 hours, the final
    /// proof 1½ to 3 hours.
    private let loaf = [
        PlanStep(instruction: "Sauerteig ansetzen und 10–14 Stunden reifen lassen", step: 1, startTime: 0, duration: 720,
                 durationWindow: 600...840),
        PlanStep(instruction: "Hauptteig kneten", step: 2, startTime: 720, duration: 20),
        PlanStep(instruction: "Stückgare", step: 3, startTime: 740, duration: 120, durationWindow: 90...180),
        PlanStep(instruction: "Bei 240 °C backen", step: 4, startTime: 860, duration: 50),
    ]

    private func plan(_ steps: [PlanStep], anchor: PlanAnchor, at date: Date) -> BakePlan {
        BakePlan(recipeName: "Brot", steps: steps, prepTime: 910, anchor: anchor,
                 date: date, languageCode: "de", preheatTime: 15, calendar: calendar)
    }

    private func suggestion(for plan: BakePlan, existing: [BakeWindow] = []) -> PlanWindowSuggestion? {
        BakePlanAdvisor.windowSuggestion(for: plan, dayStart: 6, dayEnd: 22,
                                         allowedDates: Date.distantPast...Date.distantFuture,
                                         existingWindows: existing, ovenCount: 1, bakePause: 10)
    }

    @Test("Nothing to suggest for a plan inside the day, or without windows")
    func nothingToSuggest() {
        #expect(suggestion(for: plan(loaf, anchor: .startsAt, at: time(19))) == nil)
        let plain = loaf.map { PlanStep(instruction: $0.instruction, step: $0.step, startTime: $0.startTime, duration: $0.duration) }
        #expect(suggestion(for: plan(plain, anchor: .startsAt, at: time(17))) == nil)
    }

    @Test("Started at 17:00 the kneading falls at 05:00; a starter ripening an hour longer puts it at 06:00")
    func stretchesTheStarter() throws {
        let found = try #require(suggestion(for: plan(loaf, anchor: .startsAt, at: time(17))))
        #expect(found.durations == [0: 780])
        #expect(found.changes == [PlanWindowSuggestion.Change(index: 0, instruction: loaf[0].instruction, from: 720, to: 780)])
        #expect(found.start == time(17))
        // 17:00 + 13 h + 20 min + 2 h + 50 min
        #expect(found.finish == time(9, 10, day: 10))
    }

    @Test("Finishing by 09:00 the kneading falls at 05:50; a final proof a quarter shorter is the smallest fix")
    func shortensTheProof() throws {
        let found = try #require(suggestion(for: plan(loaf, anchor: .finishesBy, at: time(9, day: 10))))
        #expect(found.durations == [2: 105])
        #expect(found.finish == time(9, day: 10))
        // Kneading at 09:00 − 105 − 20 − 50 minutes = 06:05; the starter is set 12 h before.
        #expect(found.start == time(18, 5))
    }

    @Test("An oven busy until 11:00 is waited for by letting the starter ripen longer")
    func waitsForTheOven() throws {
        let other = BakeWindow(recipeName: "Zopf", start: time(10, day: 10), end: time(11, day: 10))
        let found = try #require(suggestion(for: plan(loaf, anchor: .startsAt, at: time(20)), existing: [other]))
        // Started at 20:00 the bake would run 10:20–11:10; an hour more on the starter makes it 11:20.
        #expect(found.durations == [0: 780])
    }

    @Test("The plan with new durations keeps its date and works the start times out again")
    func withDurations() {
        let changed = plan(loaf, anchor: .startsAt, at: time(17)).withDurations([0: 780])
        #expect(changed.steps.map(\.startTime) == [0, 780, 800, 920])
        #expect(changed.steps[0].durationWindow == 600...840)
        #expect(changed.totalMinutes == 970)
        #expect(changed.date == time(17))
    }

    @Test("The grid widens when the windows would give too many combinations")
    func gridWidens() {
        #expect(BakePlanAdvisor.windowValues(in: 600...840, nominal: 720, grid: 60) == [600, 660, 720, 780, 840])
        #expect(BakePlanAdvisor.windowValues(in: 50...70, nominal: 55, grid: 15) == [50, 55, 60, 70])
    }
}
