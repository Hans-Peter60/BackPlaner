//
//  PlanTimelineTests.swift
//  BackPlanerTests
//
//  The scale and the lanes of the project-plan timeline: short steps get
//  room, a night collapses to a band, sub-steps sit on their parent's bar.
//

import BakePlannerCore
import Foundation
import Testing
@testable import BackPlaner

@Suite("The timeline's scale")
struct PlanTimelineScaleTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func time(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test("Linear between boundaries, one point per minute")
    func linearScale() {
        let scale = PlanTimelineScale(boundaries: [time(10, 9), time(10, 10), time(10, 11, 30)],
                                      pointsPerMinute: 1, calendar: calendar)
        #expect(scale.length == 150)
        #expect(scale.position(of: time(10, 10)) == 60)
        #expect(scale.position(of: time(10, 10, 30)) == 90)
        #expect(scale.position(of: time(10, 8)) == 0)
        #expect(scale.position(of: time(10, 12)) == 150)
        #expect(scale.gaps.isEmpty)
    }

    @Test("A five-minute step is stretched to the minimum, so its text has room")
    func shortIntervalsAreStretched() {
        let scale = PlanTimelineScale(boundaries: [time(10, 9), time(10, 9, 5), time(10, 10)],
                                      pointsPerMinute: 1, minimumInterval: 26, calendar: calendar)
        #expect(scale.position(of: time(10, 9, 5)) == 26)
        #expect(scale.length == 81, "\(scale.length)")
    }

    @Test("An overnight rest collapses to a band, with half an hour at full scale on either side")
    func nightCollapses() {
        // Mixed at 21:05, ripens until 09:05, baked until 10:00.
        let scale = PlanTimelineScale(boundaries: [time(10, 21, 5), time(11, 9, 5), time(11, 10)],
                                      pointsPerMinute: 1, gapEdge: 30 * 60, gapLength: 44, calendar: calendar)
        let gap = try! #require(scale.gaps.first)
        #expect(gap.start == time(10, 21, 35))
        #expect(gap.end == time(11, 8, 35))
        #expect(gap.position == 30)
        #expect(gap.length == 44)
        // 30 + 44 + 30 for the rest, then 55 minutes of baking.
        #expect(scale.position(of: time(11, 9, 5)) == 104)
        #expect(scale.length == 159, "\(scale.length)")
        // Inside the band the scale is linear across the 44 points.
        #expect(abs(scale.position(of: time(11, 3, 5)) - (30 + 22)) < 0.01)
        #expect(scale.isInGap(time(11, 3)))
        #expect(!scale.isInGap(time(11, 9)))
    }

    @Test("Ticks: the start, the resumption after the band, and the hours in between that have room")
    func ticks() {
        let scale = PlanTimelineScale(boundaries: [time(10, 21, 5), time(11, 9, 5), time(11, 12, 15)],
                                      pointsPerMinute: 1, minimumTickSpacing: 40, calendar: calendar)
        let dates = scale.ticks.map(\.date)
        #expect(dates.first == time(10, 21, 5))
        #expect(dates.contains(time(11, 9, 5)))
        // 22:00 lies 55 points after the start and within the edge, but
        // the band begins at 21:35; no hour in a band.
        #expect(!dates.contains(time(10, 22)))
        #expect(!dates.contains(time(11, 3)))
        // After the resumption: 10:00 is 55 points on — kept; 11:00, 12:00 too.
        #expect(dates.contains(time(11, 10)))
        #expect(dates.contains(time(11, 11)))
        #expect(dates.contains(time(11, 12)))
        // The first tick and the first tick of the next day start a day.
        #expect(scale.ticks.first?.startsDay == true)
        #expect(scale.ticks.first { $0.date == time(11, 9, 5) }?.startsDay == true)
        #expect(scale.ticks.first { $0.date == time(11, 10) }?.startsDay == false)
    }

    @Test("At half a point per minute every second hour is labelled")
    func sparseTicks() {
        let scale = PlanTimelineScale(boundaries: [time(10, 9), time(10, 13)],
                                      pointsPerMinute: 0.5, minimumTickSpacing: 40, calendar: calendar)
        #expect(scale.ticks.map(\.date) == [time(10, 9), time(10, 11), time(10, 13)])
    }

    @Test("A rise of three hours stays at full scale; only beyond four hours does a stretch collapse")
    func onlyLongStretchesCollapse() {
        let rise = PlanTimelineScale(boundaries: [time(10, 9), time(10, 12)], pointsPerMinute: 1, calendar: calendar)
        #expect(rise.gaps.isEmpty)
        #expect(rise.length == 180)
        let night = PlanTimelineScale(boundaries: [time(10, 9), time(10, 14)], pointsPerMinute: 1, calendar: calendar)
        #expect(night.gaps.count == 1)
        #expect(night.length == 104, "\(night.length)")
    }

    @Test("A boundary asked for more room gets it, the others keep the minimum")
    func roomAfterABoundary() {
        let scale = PlanTimelineScale(boundaries: [time(10, 9), time(10, 9, 5), time(10, 9, 10)],
                                      pointsPerMinute: 1, minimumInterval: 26,
                                      roomAfter: [time(10, 9): 34], calendar: calendar)
        #expect(scale.position(of: time(10, 9, 5)) == 34)
        #expect(scale.length == 60)
    }

    @Test("No boundaries, no scale")
    func emptyScale() {
        let scale = PlanTimelineScale(boundaries: [], pointsPerMinute: 1, calendar: calendar)
        #expect(scale.length == 0)
        #expect(scale.ticks.isEmpty)
    }
}

@Suite("The timeline's lanes")
struct PlanTimelineLaneTests {

    private let planID = UUID()
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func minute(_ offset: Int) -> Date { base.addingTimeInterval(TimeInterval(offset * 60)) }

    private func entry(_ step: Double, _ instruction: String, at start: Int, duration: Int,
                       recipe: String = "Roggenbrot", plan: UUID? = nil) -> PlanTimelineEntry {
        PlanTimelineEntry(id: "\(recipe)-\(step)-\(start)", recipeName: recipe, planID: plan ?? planID,
                          instruction: instruction, step: step, date: minute(start), duration: duration)
    }

    /// The rye bread with a rest the folds happen in, the oven switched on
    /// during the final proof, a turn-down at the start of the bake, and
    /// the finish.
    private var ryeBread: [PlanTimelineEntry] {
        [
            entry(1, "Zutaten mischen", at: 0, duration: 10),
            entry(2, "3 Stunden ruhen lassen", at: 10, duration: 180),
            entry(2.1, "Teig dehnen und falten (nach 30 Minuten).", at: 40, duration: 150),
            entry(2.2, "Teig dehnen und falten (nach 60 Minuten).", at: 70, duration: 120),
            entry(3, "Teig formen, 60 Minuten Stückgare", at: 190, duration: 60),
            entry(3.9, "Backofen anstellen (250 °C)", at: 235, duration: 15),
            entry(4, "Bei 250 Grad fallend auf 220 Grad mit Dampf backen", at: 250, duration: 20),
            entry(4.1, "Backofen auf 220 °C zurückdrehen", at: 250, duration: 0),
            entry(5, "Dampf ablassen", at: 270, duration: 40),
            entry(99, "Backvorgang ist beendet", at: 310, duration: 0),
        ]
    }

    @Test("Whole steps are bars, sub-steps inside their parent are markers, the finish is the end")
    func barsAndMarkers() throws {
        let lane = try #require(PlanTimelineLane.lanes(from: ryeBread).first)
        #expect(lane.recipeName == "Roggenbrot")
        #expect(lane.bars.map(\.entry.step) == [1, 2, 3, 4, 5])
        #expect(lane.finish == minute(310))
        #expect(lane.start == minute(0))
        #expect(lane.end == minute(310))
        #expect(lane.markers.isEmpty)

        let rest = lane.bars[1]
        #expect(rest.markers.map(\.entry.step) == [2.1, 2.2])
        #expect(rest.kind == .rest)
        // The oven step falls inside the final proof and marks it.
        #expect(lane.bars[2].markers.map(\.entry.step) == [3.9])
        #expect(lane.bars[2].markers.first?.kind == .oven)
        // The turn-down at the very start of the bake marks the bake, and
        // the bake is the one bar that needs room for a marker label.
        #expect(lane.bars[3].markers.map(\.entry.step) == [4.1])
        #expect(lane.bars[3].kind == .bake)
        #expect(lane.startsWithMarker == [minute(250)])
        #expect(lane.bars[4].kind == .oven)
        #expect(lane.bars[0].kind == .mix)
        #expect(lane.bars[2].kind == .shape)
    }

    /// The oven step is numbered after the step before the bake — the
    /// shaping, 6.9 — but is switched on during the proof, which is step 5;
    /// and a recipe may number its bake 7.1 and its steam release 7.2, so
    /// the generated turn-down is 7.2 as well. Both mark the bar they fall
    /// into, not the one their number points at.
    @Test("A sub-step marks the bar it falls into, whatever its number")
    func subStepsMarkTheBarTheyFallInto() throws {
        let entries = [
            entry(5, "Im Gärkorb reifen lassen", at: 0, duration: 120),
            entry(6, "Zu einem runden Laib formen", at: 120, duration: 5),      // after the proof? no — the recipe's order
            entry(6.9, "Backofen anstellen (250 °C)", at: 105, duration: 15),  // during the proof
            entry(7.1, "Bei 250 Grad fallend auf 220 Grad backen", at: 125, duration: 50),
            entry(7.2, "Backofen auf 220 °C zurückdrehen", at: 125, duration: 0),
            entry(7.3, "Dampf ablassen", at: 145, duration: 30),
        ]
        let lane = try #require(PlanTimelineLane.lanes(from: entries).first)
        #expect(lane.bars.map(\.entry.step) == [5, 6, 7.1])
        #expect(lane.bars[0].markers.map(\.entry.step) == [6.9])
        // Turn-down and steam release are moments of the bake, so both mark
        // it; the bake keeps the whole lane.
        #expect(lane.bars[2].markers.map(\.entry.step) == [7.2, 7.3])
        #expect(lane.bars[2].trackCount == 1)
    }

    @Test("A sub-step outside its parent is a bar of its own, or a loose marker without a duration")
    func subStepsOutsideTheParent() throws {
        let entries = [
            entry(1, "Teig formen", at: 0, duration: 20),
            entry(1.9, "Backofen anstellen (250 °C)", at: 25, duration: 15),   // after the shaping ended
            entry(2, "Backen", at: 40, duration: 50),
            entry(2.5, "Brot drehen", at: 95, duration: 0),                   // after the bake ended
        ]
        let lane = try #require(PlanTimelineLane.lanes(from: entries).first)
        #expect(lane.bars.map(\.entry.step) == [1, 1.9, 2])
        #expect(lane.markers.map(\.entry.step) == [2.5])
        #expect(lane.end == minute(95))
    }

    /// Two component preparations in one group run at the same time: the
    /// sourdough ripens for twelve hours while the soaker is mixed five
    /// minutes in. The soaker has work of its own, so it is a bar beside
    /// the sourdough, not a marker on it — and the two share the lane.
    @Test("Steps that run at the same time are dealt into tracks side by side")
    func parallelStepsShareTheLane() throws {
        let entries = [
            entry(1, "Zutaten abwiegen", at: 0, duration: 10),
            entry(2, "Sauerteig ansetzen und 12 Stunden reifen lassen", at: 10, duration: 720),
            entry(2.1, "Brühstück herstellen und quellen lassen", at: 15, duration: 15),
            entry(2.2, "Teig dehnen und falten (nach 60 Minuten).", at: 70, duration: 660),
            entry(3, "Hauptteig kneten", at: 730, duration: 15),
        ]
        let lane = try #require(PlanTimelineLane.lanes(from: entries).first)
        #expect(lane.bars.map(\.entry.step) == [1, 2, 2.1, 3])
        #expect(lane.bars.map(\.track) == [0, 0, 1, 0])
        #expect(lane.bars.map(\.trackCount) == [1, 2, 2, 1])
        // The fold stays a marker on the rest.
        #expect(lane.bars[1].markers.map(\.entry.step) == [2.2])

        // Three preparations at once need three tracks; a later bar none.
        let three = [
            entry(2.1, "Sauerteig herstellen", at: 0, duration: 600),
            entry(2.2, "Brühstück herstellen", at: 5, duration: 120),
            entry(2.3, "Quellstück herstellen", at: 10, duration: 60),
            entry(3, "Hauptteig kneten", at: 600, duration: 15),
        ]
        let lanes = PlanTimelineLane.lanes(from: three)
        #expect(lanes.first?.bars.map(\.track) == [0, 1, 2, 0])
        #expect(lanes.first?.bars.map(\.trackCount) == [3, 3, 3, 1])
    }

    @Test("One lane per plan, in the order of their first step; a recipe planned twice is two lanes")
    func onePlanPerLane() {
        let second = UUID()
        let entries = [
            entry(1, "Mischen", at: 60, duration: 10, recipe: "Baguette"),
            entry(1, "Mischen", at: 0, duration: 10),
            entry(1, "Mischen", at: 120, duration: 10, plan: second),
        ]
        let lanes = PlanTimelineLane.lanes(from: entries)
        #expect(lanes.map(\.recipeName) == ["Roggenbrot", "Baguette", "Roggenbrot"])
        #expect(lanes[2].id.planID == second)
        #expect(lanes.allSatisfy { $0.bars.count == 1 })
    }

    @Test("The kind follows the wording, in three languages")
    func kinds() {
        #expect(PlanTimelineLane.kind(of: "Hauptteig kneten", duration: 15) == .mix)
        #expect(PlanTimelineLane.kind(of: "Mix the dough", duration: 15) == .mix)
        #expect(PlanTimelineLane.kind(of: "Pétrir la pâte", duration: 15) == .mix)
        #expect(PlanTimelineLane.kind(of: "Stockgare bei 24 °C", duration: 120) == .rest)
        #expect(PlanTimelineLane.kind(of: "Bulk fermentation", duration: 120) == .rest)
        #expect(PlanTimelineLane.kind(of: "Pointage", duration: 120) == .rest)
        // Mixing and then ripening for twelve hours is a rest; a quick mix is mixing.
        #expect(PlanTimelineLane.kind(of: "Sauerteig ansetzen und 12 Stunden reifen lassen", duration: 720) == .rest)
        #expect(PlanTimelineLane.kind(of: "Sauerteig ansetzen und reifen lassen", duration: 10) == .mix)
        #expect(PlanTimelineLane.kind(of: "Teig rundwirken", duration: 10) == .shape)
        #expect(PlanTimelineLane.kind(of: "Shape the loaf", duration: 10) == .shape)
        #expect(PlanTimelineLane.kind(of: "Teig dehnen und falten (nach 30 Minuten).", duration: 90) == .fold)
        #expect(PlanTimelineLane.kind(of: "Backofen auf 250 °C vorheizen", duration: 15) == .oven)
        #expect(PlanTimelineLane.kind(of: "Dampf ablassen", duration: 30) == .oven)
        #expect(PlanTimelineLane.kind(of: "Bei 250 °C backen", duration: 50) == .bake)
        #expect(PlanTimelineLane.kind(of: "Auskühlen lassen", duration: 60) == .other)
    }
}
