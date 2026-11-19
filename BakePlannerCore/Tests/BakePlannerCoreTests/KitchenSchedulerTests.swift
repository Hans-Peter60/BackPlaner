//
//  KitchenSchedulerTests.swift
//  BakePlannerCoreTests
//
//  The step-level scheduler: one cook, burners, an oven, a budget. Small
//  kitchens first, then the three show dishes from KitchenDishes.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Kitchen scheduler: one cook, a few burners, a time budget")
struct KitchenSchedulerTests {

    private func task(_ id: String, _ name: String = "", hands: Int, unattended: Int = 0,
                      station: KitchenStation? = nil, after: [String] = []) -> KitchenTask {
        KitchenTask(id: id, name: name.isEmpty ? id : name, hands: hands, unattended: unattended, station: station, after: after)
    }

    // MARK: Placing

    @Test("The pot gets going before the knife work, and the hands fill the waiting time")
    func potFirst() throws {
        let schedule = try KitchenScheduler.schedule([
            task("sauce", hands: 8),
            task("pasta", hands: 1, unattended: 10, station: .burner),
            task("plate", hands: 2, after: ["sauce", "pasta"])
        ], budget: 15)
        #expect(schedule.placement(of: "pasta")?.start == 0)
        #expect(schedule.placement(of: "sauce")?.start == 1)
        #expect(schedule.placement(of: "plate")?.start == 11)
        #expect(schedule.makespan == 13)
        #expect(schedule.fits && schedule.slack == 2 && schedule.limit == nil)
        #expect(schedule.criticalPath == ["pasta", "plate"])
        #expect(schedule.idleHandsMinutes == 2)
    }

    @Test("The hands are never on two things at once")
    func oneCook() throws {
        let schedule = try KitchenScheduler.schedule([
            task("a", hands: 5), task("b", hands: 5), task("c", hands: 5)
        ])
        let spans = schedule.placements.map { $0.start..<$0.handsEnd }
        for (i, span) in spans.enumerated() {
            for other in spans[(i + 1)...] {
                #expect(!span.overlaps(other))
            }
        }
        #expect(schedule.makespan == 15)
    }

    @Test("Three pots on two burners: the third waits for a free one")
    func burners() throws {
        let schedule = try KitchenScheduler.schedule([
            task("p1", hands: 0, unattended: 10, station: .burner),
            task("p2", hands: 0, unattended: 10, station: .burner),
            task("p3", hands: 0, unattended: 10, station: .burner)
        ], kitchen: Kitchen(burners: 2, ovens: 0))
        #expect(schedule.makespan == 20)
        #expect(schedule.placements.filter { $0.start == 0 }.count == 2)
    }

    @Test("A step waits for every step it depends on")
    func dependencies() throws {
        let schedule = try KitchenScheduler.schedule([
            task("boil", hands: 1, unattended: 12, station: .burner),
            task("chop", hands: 3),
            task("mix", hands: 2, after: ["boil", "chop"]),
            task("fry", hands: 4, station: .burner, after: ["mix"])
        ])
        let mix = try #require(schedule.placement(of: "mix"))
        #expect(mix.start == 13)
        #expect(schedule.placement(of: "fry")?.start == 15)
        #expect(schedule.makespan == 19)
        #expect(schedule.criticalPathMinutes == 19)
    }

    @Test("The oven is one station: preheating holds it, the roast waits for the preheating")
    func oven() throws {
        let schedule = try KitchenScheduler.schedule([
            task("preheat", hands: 0, unattended: 10, station: .oven),
            task("roast", hands: 2, unattended: 20, station: .oven, after: ["preheat"]),
            task("nuts", hands: 1, unattended: 8, station: .oven, after: ["preheat"])
        ])
        // One oven: the nuts cannot share it with the roast.
        #expect(schedule.makespan == 10 + 22 + 9)
    }

    // MARK: Why a dish does not fit

    @Test("Too long a chain: no parallel work helps")
    func chainTooLong() throws {
        let schedule = try KitchenScheduler.schedule([
            task("braise", hands: 3, unattended: 40, station: .burner),
            task("plate", hands: 2, after: ["braise"])
        ], budget: 35)
        #expect(!schedule.fits)
        #expect(schedule.limit == .criticalPath)
        #expect(schedule.shortfall == 10)
        #expect(schedule.criticalPath == ["braise", "plate"])
    }

    @Test("Too much hands-on work: one pair of hands is not enough")
    func handsTooMany() throws {
        let schedule = try KitchenScheduler.schedule((1...5).map { task("t\($0)", hands: 8) }, budget: 35)
        #expect(schedule.limit == .hands)
        #expect(schedule.handsMinutes == 40)
        #expect(schedule.shortfall == 5)
    }

    @Test("Chain and hands fit, but they collide: the dish needs more than its bounds")
    func packing() throws {
        // Two chains of 20 each; the hands total 30; one cook cannot start
        // both pots at minute 0.
        let schedule = try KitchenScheduler.schedule([
            task("a1", hands: 10, station: .burner), task("a2", hands: 0, unattended: 10, after: ["a1"]),
            task("b1", hands: 10, station: .burner), task("b2", hands: 0, unattended: 10, after: ["b1"]),
            task("plate", hands: 5, after: ["a2", "b2"])
        ], budget: 32)
        #expect(schedule.criticalPathMinutes == 25)
        #expect(schedule.handsMinutes == 25)
        #expect(schedule.makespan == 35)
        #expect(schedule.limit == .packing)
    }

    @Test("Waiting: a pear glazed early waits for the plating")
    func waiting() throws {
        let schedule = try KitchenScheduler.schedule([
            task("pear", hands: 4, station: .burner),
            task("stew", hands: 2, unattended: 20, station: .burner),
            task("plate", hands: 2, after: ["pear", "stew"])
        ])
        #expect(schedule.waitingMinutes(of: "pear") == schedule.placement(of: "plate")!.start - schedule.placement(of: "pear")!.end)
        #expect(schedule.waitingMinutes(of: "stew") == 0)
        #expect(schedule.waitingMinutes(of: "plate") == 0)
    }

    @Test("The clock: a dish served at seven starts at seven minus its length")
    func servingTime() throws {
        let schedule = try KitchenScheduler.schedule([
            task("boil", hands: 1, unattended: 12, station: .burner),
            task("plate", hands: 2, after: ["boil"])
        ])
        let serving = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(schedule.startDate(of: "boil", serving: serving) == serving.addingTimeInterval(-15 * 60))
        #expect(schedule.startDate(of: "plate", serving: serving) == serving.addingTimeInterval(-2 * 60))
    }

    // MARK: Refusing bad input

    @Test("Duplicate ids, unknown dependencies, cycles and a missing oven are errors")
    func errors() {
        #expect(throws: KitchenSchedulingError.duplicateTask("a")) {
            try KitchenScheduler.schedule([task("a", hands: 1), task("a", hands: 1)])
        }
        #expect(throws: KitchenSchedulingError.unknownDependency(task: "a", dependency: "zz")) {
            try KitchenScheduler.schedule([task("a", hands: 1, after: ["zz"])])
        }
        #expect(throws: KitchenSchedulingError.cycle) {
            try KitchenScheduler.schedule([task("a", hands: 1, after: ["b"]), task("b", hands: 1, after: ["a"])])
        }
        #expect(throws: KitchenSchedulingError.stationMissing(.oven)) {
            try KitchenScheduler.schedule([task("a", hands: 1, station: .oven)], kitchen: Kitchen(burners: 2, ovens: 0))
        }
    }

    @Test("No steps: an empty plan that fits")
    func empty() throws {
        let schedule = try KitchenScheduler.schedule([], budget: 35)
        #expect(schedule.makespan == 0 && schedule.fits && schedule.criticalPath.isEmpty)
    }

    // MARK: The show dishes

    @Test("Every dish plan keeps the invariants: hands, stations, dependencies",
          arguments: [KitchenDishes.perlhuhnbrust, KitchenDishes.wirsingrolle, KitchenDishes.geschnetzeltes])
    func dishInvariants(_ tasks: [KitchenTask]) throws {
        let kitchen = Kitchen(burners: 4, ovens: 1)
        let schedule = try KitchenScheduler.schedule(tasks, kitchen: kitchen, budget: KitchenDishes.budget)
        #expect(schedule.placements.count == tasks.count)
        for placement in schedule.placements {
            for dependency in placement.task.after {
                #expect(try #require(schedule.placement(of: dependency)).end <= placement.start, "\(placement.task.id) before \(dependency)")
            }
        }
        for minute in 0..<schedule.makespan {
            let hands = schedule.placements.filter { $0.task.handsMinutes > 0 && ($0.start..<$0.handsEnd).contains(minute) }
            #expect(hands.count <= 1, "minute \(minute): \(hands.map(\.task.id))")
            for station in [KitchenStation.burner, .oven] {
                let busy = schedule.placements.filter { $0.task.station == station && ($0.start..<$0.end).contains(minute) }
                #expect(busy.count <= kitchen.capacity(of: station), "minute \(minute): \(station) \(busy.map(\.task.id))")
            }
        }
        #expect(schedule.makespan >= schedule.criticalPathMinutes)
        #expect(schedule.makespan >= schedule.handsMinutes)
    }

    @Test("Perlhuhnbrust with four pans: the hands are the limit, not the chain")
    func perlhuhnbrust() throws {
        let schedule = try KitchenScheduler.schedule(KitchenDishes.perlhuhnbrust, budget: KitchenDishes.budget)
        #expect(schedule.criticalPathMinutes < KitchenDishes.budget)
        #expect(schedule.handsMinutes > KitchenDishes.budget)
        #expect(schedule.limit == .hands)
        #expect(schedule.handsByComponent.first?.component == "Wirsing")
    }

    @Test("Wirsingrolle: the barley's 25 minutes plus filling, rolling and browning do not fit 35")
    func wirsingrolle() throws {
        let schedule = try KitchenScheduler.schedule(KitchenDishes.wirsingrolle, budget: KitchenDishes.budget)
        #expect(schedule.criticalPath.first == "r1")
        #expect(schedule.criticalPath.last == "x1")
        #expect(schedule.criticalPathMinutes == 2 + 25 + 3 + 5 + 3)
        #expect(!schedule.fits)
        // Both bounds are over; the hands more so.
        #expect(schedule.limit == .hands)
    }

    @Test("Geschnetzeltes: the skin in the oven sets the chain, and it just does not fit")
    func geschnetzeltes() throws {
        let schedule = try KitchenScheduler.schedule(KitchenDishes.geschnetzeltes, budget: KitchenDishes.budget)
        #expect(schedule.criticalPath == ["o1", "h1", "h2", "h3", "x1"])
        #expect(schedule.criticalPathMinutes == 10 + 2 + 20 + 1 + 3)
        #expect(!schedule.fits)
        // With a second cook the chain would still be a minute over the budget.
        #expect(schedule.criticalPathMinutes == KitchenDishes.budget + 1)
    }

    @Test("A second pair of hands is not modelled, but a wider budget shows the chain alone")
    func widerBudget() throws {
        let schedule = try KitchenScheduler.schedule(KitchenDishes.perlhuhnbrust, budget: 60)
        #expect(schedule.fits)
        #expect(schedule.limit == nil)
    }
}
