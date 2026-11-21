//
//  KitchenCookRunTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("A dish cooked on the stopwatch")
struct KitchenCookRunTests {

    @Test("Steps come in the order they were done, with their actual time and the difference to the plan")
    func steps() throws {
        let run = KitchenCookRun(dishID: "d", dishName: "Gericht", startedAt: Date(timeIntervalSince1970: 0),
                                 totalSeconds: 2_100, plannedMinutes: 35, steps: [
            .init(taskID: "b", name: "Braten", component: "Fleisch", plannedMinutes: 5, plannedStart: 6,
                  startedSecond: 420, doneSecond: 800, tickedByCook: true),
            .init(taskID: "a", name: "Schneiden", component: "Fleisch", plannedMinutes: 6, plannedStart: 0,
                  startedSecond: 0, doneSecond: 330, tickedByCook: true),
        ])
        #expect(run.steps.map(\.taskID) == ["a", "b"])
        #expect(run.steps[0].actualSeconds == 330 && run.steps[0].differenceSeconds == -30)
        #expect(run.steps[1].actualSeconds == 380 && run.steps[1].differenceSeconds == 80)
        #expect(KitchenCookRun.clockText(2_100) == "35:00")
        #expect(KitchenCookRun.clockText(3_723) == "1:02:03")
        #expect(KitchenCookRun.differenceText(80) == "+1:20" && KitchenCookRun.differenceText(-30) == "−0:30")

        #expect(run.isComplete)
        var partial = run
        partial.totalSteps = 5
        #expect(!partial.isComplete)

        let data = try JSONEncoder().encode(run)
        #expect(try JSONDecoder().decode(KitchenCookRun.self, from: data) == run)
    }

    @Test("A step cannot be done before it began")
    func clamped() {
        let step = KitchenCookRun.Step(taskID: "x", name: "x", component: "", plannedMinutes: 2, plannedStart: 3,
                                       startedSecond: 200, doneSecond: 150, tickedByCook: true)
        #expect(step.actualSeconds == 0)
    }

    @Test("A record from before rating, note and photo still reads, and keeps them once given")
    func impression() throws {
        let old = #"{"id":"r","dishID":"d","dishName":"Test","startedAt":"2026-11-21T18:00:00Z","totalSeconds":600,"plannedMinutes":10,"steps":[]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var run = try decoder.decode(KitchenCookRun.self, from: Data(old.utf8))
        #expect(run.rating == nil && run.note == nil && run.photoFileName == nil)
        #expect(!run.hasImpression)
        run.rating = 4
        run.note = "Etwas mehr Salz"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let again = try decoder.decode(KitchenCookRun.self, from: encoder.encode(run))
        #expect(again.rating == 4 && again.note == "Etwas mehr Salz")
        #expect(again.hasImpression)
    }
}
