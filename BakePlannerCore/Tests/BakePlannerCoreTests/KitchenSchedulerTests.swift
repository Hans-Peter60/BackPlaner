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
                      station: KitchenStation? = nil, after: [String] = [], maxWait: Int? = nil) -> KitchenTask {
        KitchenTask(id: id, name: name.isEmpty ? id : name, hands: hands, unattended: unattended, station: station,
                    after: after, maxWait: maxWait)
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

    @Test("One oven, one temperature: the nuts go in beside the roast; at another temperature they wait")
    func oven() throws {
        func dish(nutsAt temperature: Int?) -> [KitchenTask] {
            [
                KitchenTask(id: "roast", name: "Braten", hands: 2, unattended: 20, station: .oven, ovenTemperature: 160),
                KitchenTask(id: "nuts", name: "Nüsse", hands: 1, unattended: 8, station: .oven, ovenTemperature: temperature)
            ]
        }
        let shared = try KitchenScheduler.schedule(dish(nutsAt: 160))
        #expect(shared.placement(of: "nuts")?.start == 2)
        #expect(shared.makespan == 22)
        let hotter = try KitchenScheduler.schedule(dish(nutsAt: 220))
        #expect(hotter.placement(of: "nuts")?.start == 22)
        #expect(hotter.makespan == 31)
        // Without a temperature of its own the step takes the oven as it is.
        let any = try KitchenScheduler.schedule(dish(nutsAt: nil))
        #expect(any.placement(of: "nuts")?.start == 2)
        // A second oven takes the other temperature.
        let twoOvens = try KitchenScheduler.schedule(dish(nutsAt: 220), kitchen: Kitchen(burners: 4, ovens: 2))
        #expect(twoOvens.placement(of: "nuts")?.start == 2)
        #expect(twoOvens.makespan == 22)
    }

    @Test("A step that is not in the oven carries no oven temperature")
    func temperatureOnlyInTheOven() {
        #expect(KitchenTask(id: "a", name: "a", hands: 1, station: .burner, ovenTemperature: 200).ovenTemperature == nil)
        #expect(KitchenTask(id: "b", name: "b", hands: 1, station: .oven, ovenTemperature: 200).ovenTemperature == 200)
    }

    @Test("Replanning keeps the running oven's temperature: the gratin waits for the skin")
    func runningOvenTemperature() throws {
        let tasks = [
            KitchenTask(id: "skin", name: "Haut", hands: 0, unattended: 20, station: .oven, ovenTemperature: 160),
            task("prep", hands: 3),
            KitchenTask(id: "gratin", name: "Gratin", hands: 1, unattended: 10, station: .oven, after: ["prep"], ovenTemperature: 220),
            task("plate", hands: 1, after: ["skin", "gratin"])
        ]
        let plan = try KitchenScheduler.schedule(tasks)
        #expect(plan.placement(of: "gratin")?.start == 20)
        let live = try KitchenScheduler.replan(tasks, previous: plan, progress: KitchenProgress(now: 5, finished: ["prep": 2]))
        #expect(live.placement(of: "gratin")?.start == 20)
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

    // MARK: Follow-ups that cannot wait

    @Test("The seared breast is turned at once: the hands stay free for it, a short job still fits in")
    func turnedAtOnce() throws {
        let schedule = try KitchenScheduler.schedule([
            task("sear", hands: 1, unattended: 5, station: .burner, maxWait: 0),
            task("turn", hands: 3, station: .burner, after: ["sear"]),
            task("k1", hands: 4),
            task("k2", hands: 3),
            task("k3", hands: 1),
            task("plate", hands: 1, after: ["turn", "k1", "k2", "k3"])
        ])
        #expect(schedule.placement(of: "sear")?.start == 0)
        #expect(schedule.placement(of: "k1")?.start == 1)
        // k2 would run past minute 6; the one-minute job fits, k2 waits.
        #expect(schedule.placement(of: "k3")?.start == 5)
        #expect(schedule.placement(of: "turn")?.start == 6)
        #expect(schedule.placement(of: "k2")?.start == 9)
        #expect(schedule.lateFollowUps.isEmpty)
    }

    @Test("Without the rule the breast would wait in the pan")
    func withoutTheRule() throws {
        let schedule = try KitchenScheduler.schedule([
            task("sear", hands: 1, unattended: 5, station: .burner),
            task("turn", hands: 3, station: .burner, after: ["sear"]),
            task("k1", hands: 4),
            task("k2", hands: 3),
            task("plate", hands: 1, after: ["turn", "k1", "k2"])
        ])
        #expect(schedule.placement(of: "turn")?.start == 8)
        #expect(schedule.waitingMinutes(of: "sear") == 2)
    }

    @Test("Rested meat is sliced within its minutes, not when the hands happen to be free")
    func restedMeat() throws {
        let schedule = try KitchenScheduler.schedule([
            task("rest", hands: 0, unattended: 5, maxWait: 3),
            task("slice", hands: 2, after: ["rest"]),
            task("long", hands: 12),
            task("plate", hands: 1, after: ["slice", "long"])
        ])
        // The long job would run to minute 12, past the slicing's moment 8.
        #expect(schedule.placement(of: "slice")?.start == 5)
        #expect(schedule.placement(of: "long")?.start == 7)
        #expect(schedule.lateFollowUps.isEmpty)
    }

    @Test("Work the follow-up still waits for is never held back; the predecessor is held back instead")
    func heldBack() throws {
        // q becomes possible only at minute 1, after s would have started;
        // the first attempt has d three minutes late, so s waits for q.
        let schedule = try KitchenScheduler.schedule([
            task("s", hands: 1, unattended: 1, maxWait: 0),
            task("w", hands: 0, unattended: 1),
            task("q", hands: 4, after: ["w"]),
            task("d", hands: 1, after: ["s", "q"])
        ])
        #expect(schedule.placement(of: "q")?.start == 1)
        #expect(schedule.placement(of: "s")?.start == 5)
        #expect(schedule.placement(of: "d")?.start == 7)
        #expect(schedule.lateFollowUps.isEmpty)
    }

    @Test("A follow-up that waits for a station: its predecessor is held back until the station is free")
    func heldBackForStation() throws {
        // The frying needs the only burner, which the stew holds until 20;
        // the rest is not begun until the pan is about to be free.
        let schedule = try KitchenScheduler.schedule([
            task("stew", hands: 1, unattended: 19, station: .burner),
            task("rest", hands: 0, unattended: 2, maxWait: 0),
            task("fry", hands: 2, station: .burner, after: ["rest"]),
            task("chop", hands: 5),
            task("plate", hands: 1, after: ["fry", "chop", "stew"])
        ], kitchen: Kitchen(burners: 1, ovens: 0))
        #expect(schedule.placement(of: "rest")?.start == 18)
        #expect(schedule.placement(of: "fry")?.start == 20)
        #expect(schedule.placement(of: "chop")?.start == 1)
        #expect(schedule.lateFollowUps.isEmpty)
        #expect(schedule.makespan == 23)
    }

    @Test("Two things one cook must finish at the same moment: the lateness that remains is reported")
    func unavoidableLateness() throws {
        let schedule = try KitchenScheduler.schedule([
            task("s1", hands: 5, maxWait: 0),
            task("s2", hands: 5, maxWait: 0),
            task("d", hands: 1, after: ["s1", "s2"])
        ])
        #expect(schedule.placements.count == 3)
        #expect(schedule.lateFollowUps.count == 1)
        #expect(schedule.lateFollowUps.first?.minutes == 5)
        #expect(schedule.makespan == 11)
    }

    @Test("Holding back is worth it only while it saves more freshness than it costs: three pans that all want the plate at once keep the hands busy instead")
    func holdBackWeighedAgainstLength() throws {
        // Three components, each a prep and a hands-on pan step whose
        // result must go straight to the plate. One cook cannot finish
        // three pans at once; holding every pan back until the plate is
        // free would leave the hands idle for twenty minutes. The plan
        // keeps the hands busy (27 minutes, the hands total) and reports
        // the two pans that stand.
        var tasks = [KitchenTask]()
        for i in 1...3 {
            tasks.append(task("prep\(i)", hands: 3))
            tasks.append(task("cook\(i)", hands: 5, station: .burner, after: ["prep\(i)"], maxWait: 0))
        }
        tasks.append(task("plate", hands: 3, after: ["cook1", "cook2", "cook3"]))
        let schedule = try KitchenScheduler.schedule(tasks, budget: 35)
        #expect(schedule.makespan == 27)
        #expect(schedule.lateFollowUps.reduce(0) { $0 + $1.minutes } == 15)
    }

    @Test("Long waits are listed for keeping warm, longest first")
    func keepWarm() throws {
        let schedule = try KitchenScheduler.schedule([
            task("pear", hands: 4, station: .burner),
            task("sauce", hands: 2, unattended: 6, station: .burner),
            task("stew", hands: 2, unattended: 24, station: .burner),
            task("plate", hands: 2, after: ["pear", "sauce", "stew"])
        ])
        let waits = schedule.waits(atLeast: 10)
        #expect(waits.map(\.task) == ["pear", "sauce"])
        #expect(waits.first?.minutes == 26 - 8)
        #expect(schedule.waits(atLeast: 30).isEmpty)
    }

    // MARK: Replanning while cooking

    @Test("A pot that boiled early pulls its follow-up forward")
    func finishedEarly() throws {
        let tasks = [
            task("pasta", hands: 1, unattended: 10, station: .burner),
            task("sauce", hands: 4),
            task("plate", hands: 2, after: ["pasta", "sauce"])
        ]
        let plan = try KitchenScheduler.schedule(tasks)
        #expect(plan.placement(of: "plate")?.start == 11)
        let live = try KitchenScheduler.replan(tasks, previous: plan, progress: KitchenProgress(now: 7, finished: ["pasta": 6, "sauce": 5]))
        #expect(live.placement(of: "pasta")?.end == 6)
        #expect(live.placement(of: "sauce")?.end == 5)
        #expect(live.placement(of: "plate")?.start == 7)
        #expect(live.makespan == 9)
    }

    @Test("Chopping that is not ticked off holds the hands; everything behind it moves")
    func runningLate() throws {
        let tasks = [
            task("chop", hands: 3),
            task("fry", hands: 4, station: .burner, after: ["chop"]),
            task("plate", hands: 1, after: ["fry"])
        ]
        let plan = try KitchenScheduler.schedule(tasks)
        #expect(plan.makespan == 8)
        let live = try KitchenScheduler.replan(tasks, previous: plan, progress: KitchenProgress(now: 5))
        // Minute 5, the chopping (planned 0–3) is still going: it is taken
        // to need until minute 6, and the frying waits for it.
        #expect(live.placement(of: "chop")?.end == 6)
        #expect(live.placement(of: "fry")?.start == 6)
        #expect(live.makespan == 11)
        // Ticked off at minute 5, it ends there.
        let done = try KitchenScheduler.replan(tasks, previous: plan, progress: KitchenProgress(now: 5, finished: ["chop": 5]))
        #expect(done.placement(of: "chop")?.end == 5)
        #expect(done.placement(of: "fry")?.start == 5)
        #expect(done.makespan == 10)
    }

    @Test("A step with an unattended part ends when planned, ticked off or not; ticked off early it ends then")
    func unattendedByTime() throws {
        let tasks = [
            task("stew", hands: 2, unattended: 20, station: .burner),
            task("plate", hands: 1, after: ["stew"])
        ]
        let plan = try KitchenScheduler.schedule(tasks)
        let live = try KitchenScheduler.replan(tasks, previous: plan, progress: KitchenProgress(now: 25))
        #expect(live.placement(of: "stew")?.end == 22)
        // The plating began at 22 as planned and is overdue, not ticked off.
        #expect(live.placement(of: "plate")?.start == 22)
        #expect(live.placement(of: "plate")?.end == 26)
        let early = try KitchenScheduler.replan(tasks, previous: plan, progress: KitchenProgress(now: 15, finished: ["stew": 15]))
        #expect(early.placement(of: "plate")?.start == 15)
        let plated = try KitchenScheduler.replan(tasks, previous: plan, progress: KitchenProgress(now: 25, finished: ["plate": 24]))
        #expect(plated.placement(of: "plate")?.end == 24)
        #expect(plated.makespan == 24)
    }

    @Test("What is running keeps its station: the only burner stays taken until the stew is done")
    func runningStation() throws {
        let tasks = [
            task("stew", hands: 1, unattended: 19, station: .burner),
            task("chop", hands: 2),
            task("fry", hands: 3, station: .burner, after: ["chop"]),
            task("plate", hands: 1, after: ["stew", "fry"])
        ]
        let plan = try KitchenScheduler.schedule(tasks, kitchen: Kitchen(burners: 1, ovens: 0))
        let live = try KitchenScheduler.replan(tasks, kitchen: Kitchen(burners: 1, ovens: 0), previous: plan,
                                               progress: KitchenProgress(now: 4, finished: ["chop": 4]))
        #expect(live.placement(of: "fry")?.start == 20)
    }

    @Test("Replanning the show dish from the middle keeps the invariants and never moves what happened")
    func replanDish() throws {
        let tasks = KitchenSampleDishes.perlhuhnbrust.tasks
        let plan = try KitchenScheduler.schedule(tasks, budget: KitchenSampleDishes.budget)
        var finished = [String: Int]()
        for placement in plan.placements where placement.task.unattendedMinutes == 0 && placement.task.handsMinutes > 0 && placement.end <= 20 {
            finished[placement.task.id] = placement.end + 1   // every chop a minute late
        }
        let live = try KitchenScheduler.replan(tasks, budget: KitchenSampleDishes.budget, previous: plan,
                                               progress: KitchenProgress(now: 20, finished: finished))
        #expect(live.placements.count == tasks.count)
        for (id, minute) in finished {
            #expect(live.placement(of: id)?.end == minute)
        }
        for placement in live.placements where placement.start >= 20 {
            for dependency in placement.task.after {
                #expect(try #require(live.placement(of: dependency)).end <= placement.start, "\(placement.task.id) before \(dependency)")
            }
        }
        for minute in 20..<live.makespan {
            let hands = live.placements.filter { $0.task.handsMinutes > 0 && ($0.start..<$0.handsEnd).contains(minute) }
            #expect(hands.count <= 1, "minute \(minute): \(hands.map(\.task.id))")
        }
        #expect(live.makespan >= plan.makespan)
    }

    @Test("Continued minute by minute from the last live plan, the plan stands still; from the original it would slide")
    func continuedPlanStandsStill() throws {
        let tasks = KitchenSampleDishes.geschnetzeltes.tasks
        let plan = try KitchenScheduler.schedule(tasks, budget: KitchenSampleDishes.budget)
        // The first chopping is ticked off the moment the clock starts.
        var finished = ["m1": 0]
        var live = try KitchenScheduler.replan(tasks, budget: KitchenSampleDishes.budget, previous: plan,
                                               progress: KitchenProgress(now: 0, finished: finished))
        let pulledForward = live.makespan
        #expect(pulledForward == plan.makespan - 6)
        #expect(live.placement(of: "h1")?.start == 0)
        for minute in 1...5 {
            // The skin goes into the oven on time, ticked off at minute 2.
            if minute == 2 { finished["h1"] = 2 }
            live = try KitchenScheduler.replan(tasks, budget: KitchenSampleDishes.budget, previous: live,
                                               progress: KitchenProgress(now: minute, finished: finished))
            #expect(live.makespan == pulledForward, "minute \(minute)")
            #expect(live.placement(of: "h1")?.start == 0, "minute \(minute)")
        }
        // Begun steps keep their start when the plan is continued.
        let begun = live.placements.filter { $0.start < 5 && $0.task.handsMinutes > 0 }
        #expect(!begun.isEmpty)
    }

    @Test("A tick taken back: the step is in the hands again, overdue, and what had moved up waits for it")
    func tickTakenBack() throws {
        let tasks = [
            task("chop", hands: 4),
            task("dice", hands: 3),
            task("fry", hands: 2, station: .burner, after: ["chop", "dice"]),
            task("plate", hands: 1, after: ["fry"])
        ]
        let plan = try KitchenScheduler.schedule(tasks)
        // Ticked off at minute 1 by mistake: the dicing moves up to minute 1.
        let ticked = try KitchenScheduler.replan(tasks, previous: plan, progress: KitchenProgress(now: 1, finished: ["chop": 1]))
        #expect(ticked.placement(of: "dice")?.start == 1)
        // Taken back at minute 2: the chopping holds the hands again, the
        // dicing that had begun in the live plan cannot have, and waits.
        let undone = try KitchenScheduler.replan(tasks, previous: ticked, progress: KitchenProgress(now: 2))
        let chop = try #require(undone.placement(of: "chop"))
        #expect(chop.start == 0)
        #expect(chop.end == 4)
        #expect(try #require(undone.placement(of: "dice")).start >= chop.end)
        #expect(undone.lateFollowUps.isEmpty)
    }

    // MARK: Windows

    @Test("A window holds the planned minutes and says how far they can be cut")
    func window() {
        let bake = task("bake", hands: 0, unattended: 25, station: .oven)
        #expect(bake.unattendedWindow == nil && bake.reducibleMinutes == 0)
        let windowed = KitchenTask(id: "skin", name: "Haut backen", hands: 0, unattended: 25, station: .oven, window: 20...25)
        #expect(windowed.reducibleMinutes == 5)
        #expect(windowed.shortened(to: 22).unattendedMinutes == 22)
        #expect(windowed.shortened(to: 10).unattendedMinutes == 20)
        let clamped = KitchenTask(id: "x", name: "x", hands: 0, unattended: 30, window: 20...25)
        #expect(clamped.unattendedMinutes == 25)
    }

    @Test("Too long a chain is cut within the windows of its steps, no further than the budget needs")
    func fitByCutting() throws {
        let tasks = [
            KitchenTask(id: "skin", name: "Haut backen", hands: 2, unattended: 25, station: .oven, window: 20...25),
            KitchenTask(id: "rest", name: "Ruhen", hands: 0, unattended: 8, after: ["skin"], window: 5...8),
            task("plate", hands: 3, after: ["rest"]),
            task("chop", hands: 10)
        ]
        let nominal = try KitchenScheduler.schedule(tasks, budget: 35)
        #expect(nominal.makespan == 38 && nominal.limit == .criticalPath)
        let fit = try KitchenScheduler.fit(tasks, budget: 35)
        #expect(fit.schedule.fits)
        #expect(fit.schedule.makespan == 35)
        // The skin has the most to give and is cut first, by the three
        // minutes missing; the rest is left alone.
        #expect(fit.shortenings == [KitchenShortening(task: "skin", from: 25, to: 22)])
    }

    @Test("Cutting stops at the windows: what still does not fit says so")
    func fitLimited() throws {
        let tasks = [
            KitchenTask(id: "skin", name: "Haut backen", hands: 2, unattended: 25, station: .oven, window: 20...25),
            task("plate", hands: 3, after: ["skin"])
        ]
        let fit = try KitchenScheduler.fit(tasks, budget: 20)
        #expect(!fit.schedule.fits)
        #expect(fit.schedule.makespan == 25)
        #expect(fit.shortenings == [KitchenShortening(task: "skin", from: 25, to: 20)])
    }

    @Test("A dish the hands do not fit is not cut: shorter cooking frees no hands")
    func fitHands() throws {
        let fit = try KitchenScheduler.fit(KitchenSampleDishes.perlhuhnbrust.tasks, budget: KitchenSampleDishes.budget)
        #expect(fit.shortenings.isEmpty)
        #expect(fit.schedule.limit == .hands)
    }

    @Test("Past its planned end without a tick, a windowed step goes on until the window's end")
    func windowedStepRuns() throws {
        let tasks = [
            KitchenTask(id: "skin", name: "Haut backen", hands: 2, unattended: 20, station: .oven, window: 20...25),
            task("plate", hands: 3, after: ["skin"])
        ]
        let plan = try KitchenScheduler.schedule(tasks)
        #expect(plan.placement(of: "plate")?.start == 22)
        // Minute 23, not ticked: still in the oven, the plating waits.
        let running = try KitchenScheduler.replan(tasks, previous: plan, progress: KitchenProgress(now: 23))
        #expect(running.placement(of: "skin")?.end == 24)
        #expect(running.placement(of: "plate")?.start == 24)
        // Minute 30: the window ended at 27; the skin is done by the clock.
        let late = try KitchenScheduler.replan(tasks, previous: plan, progress: KitchenProgress(now: 30))
        #expect(late.placement(of: "skin")?.end == 27)
        #expect(late.placement(of: "plate")?.start == 30)
        // Ticked off at 21: out early.
        let early = try KitchenScheduler.replan(tasks, previous: plan, progress: KitchenProgress(now: 21, finished: ["skin": 21]))
        #expect(early.placement(of: "plate")?.start == 21)
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

    @Test("The sample dishes name their parts and have no step that heats an oven: it is preheated before the clock starts")
    func sampleDishes() {
        #expect(KitchenSampleDishes.all.count == 3)
        #expect(KitchenSampleDishes.perlhuhnbrust.components.first == "Perlhuhnbrust")
        for dish in KitchenSampleDishes.all {
            #expect(!dish.tasks.contains { $0.name.lowercased().contains("vorheizen") }, "\(dish.name)")
            #expect(dish.tasks.last?.name == "Anrichten", "\(dish.name)")
        }
    }

    @Test("Every dish plan keeps the invariants: hands, stations, dependencies",
          arguments: [KitchenSampleDishes.perlhuhnbrust.tasks, KitchenSampleDishes.wirsingrolle.tasks, KitchenSampleDishes.geschnetzeltes.tasks])
    func dishInvariants(_ tasks: [KitchenTask]) throws {
        let kitchen = Kitchen(burners: 4, ovens: 1)
        let schedule = try KitchenScheduler.schedule(tasks, kitchen: kitchen, budget: KitchenSampleDishes.budget)
        #expect(schedule.placements.count == tasks.count)
        for placement in schedule.placements {
            for dependency in placement.task.after {
                #expect(try #require(schedule.placement(of: dependency)).end <= placement.start, "\(placement.task.id) before \(dependency)")
            }
        }
        for minute in 0..<schedule.makespan {
            let hands = schedule.placements.filter { $0.task.handsMinutes > 0 && ($0.start..<$0.handsEnd).contains(minute) }
            #expect(hands.count <= 1, "minute \(minute): \(hands.map(\.task.id))")
            let burners = schedule.placements.filter { $0.task.station == .burner && ($0.start..<$0.end).contains(minute) }
            #expect(burners.count <= kitchen.burners, "minute \(minute): burners \(burners.map(\.task.id))")
            // One oven: everything in it at once shares one temperature.
            let inOven = schedule.placements.filter { $0.task.station == .oven && ($0.start..<$0.end).contains(minute) }
            #expect(Set(inOven.compactMap(\.task.ovenTemperature)).count <= kitchen.ovens, "minute \(minute): oven \(inOven.map(\.task.id))")
        }
        #expect(schedule.makespan >= schedule.criticalPathMinutes)
        #expect(schedule.makespan >= schedule.handsMinutes)
        #expect(schedule.lateFollowUps.isEmpty, "\(schedule.lateFollowUps)")
    }

    @Test("Perlhuhnbrust with four pans: the hands are the limit, not the chain")
    func perlhuhnbrust() throws {
        let schedule = try KitchenScheduler.schedule(KitchenSampleDishes.perlhuhnbrust.tasks, budget: KitchenSampleDishes.budget)
        #expect(schedule.criticalPathMinutes < KitchenSampleDishes.budget)
        #expect(schedule.handsMinutes > KitchenSampleDishes.budget)
        #expect(schedule.limit == .hands)
        #expect(schedule.handsByComponent.first?.component == "Wirsing")
        // The breast is turned the moment its skin is done, and sliced
        // within three minutes of its rest.
        let seared = try #require(schedule.placement(of: "a2"))
        #expect(schedule.placement(of: "a3")?.start == seared.end)
        let rested = try #require(schedule.placement(of: "a4"))
        #expect(try #require(schedule.placement(of: "a5")).start - rested.end <= 3)
    }

    @Test("Wirsingrolle: the barley's 25 minutes plus filling, rolling and browning do not fit 35")
    func wirsingrolle() throws {
        let schedule = try KitchenScheduler.schedule(KitchenSampleDishes.wirsingrolle.tasks, budget: KitchenSampleDishes.budget)
        #expect(schedule.criticalPath.first == "r1")
        #expect(schedule.criticalPath.last == "x1")
        #expect(schedule.criticalPathMinutes == 2 + 25 + 3 + 5 + 3)
        #expect(!schedule.fits)
        // Both bounds are over; the hands more so.
        #expect(schedule.limit == .hands)
    }

    @Test("Geschnetzeltes: the skin in the oven sets the chain, the hands do not fit by two minutes")
    func geschnetzeltes() throws {
        let schedule = try KitchenScheduler.schedule(KitchenSampleDishes.geschnetzeltes.tasks, budget: KitchenSampleDishes.budget)
        // The oven is hot when the clock starts; the chain is the skin.
        #expect(schedule.criticalPath == ["m1", "h1", "h2", "h3", "x1"])
        #expect(schedule.criticalPathMinutes == 6 + 2 + 20 + 1 + 3)
        #expect(!schedule.fits)
        #expect(schedule.limit == .hands)
        #expect(schedule.shortfall == 2)
        // The sauce is finished late, so the meat does not stand around.
        let sauce = try #require(schedule.placement(of: "m3"))
        #expect(try #require(schedule.placement(of: "m4")).start - sauce.end <= 10)
    }

    @Test("A second pair of hands is not modelled, but a wider budget shows the chain alone")
    func widerBudget() throws {
        let schedule = try KitchenScheduler.schedule(KitchenSampleDishes.perlhuhnbrust.tasks, budget: 60)
        #expect(schedule.fits)
        #expect(schedule.limit == nil)
    }
}
