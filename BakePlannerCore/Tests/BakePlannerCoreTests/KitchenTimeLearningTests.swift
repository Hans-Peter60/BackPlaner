//
//  KitchenTimeLearningTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Learning a dish's minutes from the stopwatch")
struct KitchenTimeLearningTests {

    private let dish = KitchenDish(id: "d", name: "Gericht", tasks: [
        KitchenTask(id: "chop", name: "Schneiden", hands: 6),
        KitchenTask(id: "pot", name: "Köcheln", hands: 1, unattended: 10, station: .burner, after: ["chop"], window: 8...12),
        KitchenTask(id: "plate", name: "Anrichten", hands: 2, after: ["pot"]),
    ])

    private func run(_ steps: [(String, Int, Bool)], id: String) -> KitchenCookRun {
        KitchenCookRun(id: id, dishID: "d", dishName: "Gericht", startedAt: Date(timeIntervalSince1970: 0),
                       totalSeconds: 1_200, plannedMinutes: 19, steps: steps.map { task, seconds, ticked in
            .init(taskID: task, name: task, component: "", plannedMinutes: 0, plannedStart: 0,
                  startedSecond: 0, doneSecond: seconds, tickedByCook: ticked)
        })
    }

    @Test("The median of the latest runs; a pot keeps its hands and learns the rest; unticked steps and small differences teach nothing")
    func suggestions() {
        let runs = [
            run([("chop", 240, true), ("pot", 900, true), ("plate", 150, true)], id: "1"),
            run([("chop", 300, true), ("pot", 780, true), ("plate", 100, true)], id: "2"),
            run([("chop", 600, true), ("pot", 660, false)], id: "3"),
        ]
        let found = KitchenTimeLearning.suggestions(for: dish, from: runs)
        #expect(found.map(\.taskID) == ["chop", "pot"])
        #expect(found[0].hands == 5 && found[0].runs == 3)          // median 300 s
        #expect(found[1].hands == 1 && found[1].unattended == 13)   // median 840 s = 14 min, hands 1
        // "plate": median 125 s ≈ 2 min — as planned, no suggestion.

        let applied = KitchenTimeLearning.applying(found, to: dish)
        #expect(applied.tasks[0].handsMinutes == 5)
        #expect(applied.tasks[1].unattendedMinutes == 13 && applied.tasks[1].unattendedWindow == 8...13)
        #expect(applied.tasks[2] == dish.tasks[2])
    }

    @Test("Only the latest five runs of this dish count")
    func latestRunsOnly() {
        var runs = (0..<5).map { run([("chop", 120, true)], id: "new\($0)") }
        runs += (0..<5).map { run([("chop", 1_200, true)], id: "old\($0)") }
        var other = run([("chop", 3_000, true)], id: "x")
        other.dishID = "other"
        let found = KitchenTimeLearning.suggestions(for: dish, from: [other] + runs)
        #expect(found.first?.hands == 2 && found.first?.runs == 5)
        #expect(KitchenTimeLearning.suggestions(for: dish, from: []).isEmpty)
    }
}
