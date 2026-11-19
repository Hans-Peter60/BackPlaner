//
//  KitchenScheduler.swift
//  BakePlannerCore
//
//  One cook, a few burners, one oven and a time budget: the order in which
//  the work of a dish gets done so that everything is ready together. A
//  step binds the cook's hands for a while ("Zwiebeln würfeln", 2 min) and
//  may then run on its own ("Graupen 25 Minuten kochen") while it keeps a
//  burner or the oven; a step may have to wait for others ("Füllung
//  mischen" needs the barley, the meat and the mushrooms). The scheduler
//  places every step forward from minute 0 — hands never on two things,
//  never more pans than burners — and says whether the dish fits the budget
//  and, if not, why: the longest chain of steps is too long, or the hands
//  alone have more to do than the budget allows.
//
//  This is the planning core for the "cook against the clock" idea
//  (docs/Idee-Gegen-die-Uhr.md); BakePlan plans a bread's steps in their
//  recipe order and cannot reorder them, which a dish of four components
//  needs.
//

import Foundation

/// Where a step happens while it runs: it holds the place from its start to
/// its end, hands or no hands.
public enum KitchenStation: String, Equatable, Hashable, Sendable {
    case burner
    case oven
}

/// One piece of work. `handsMinutes` is attended work at the start of the
/// step; `unattendedMinutes` follow it without the cook ("kochen lassen").
/// A step with no hands and no station is a plain wait ("ruhen lassen").
public struct KitchenTask: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// The part of the dish the step belongs to: "Perlhuhnbrust", "Wirsing".
    public let component: String
    public let handsMinutes: Int
    public let unattendedMinutes: Int
    public let station: KitchenStation?
    /// Ids of the steps that must be finished before this one starts.
    public let after: [String]

    public init(id: String, name: String, component: String = "",
                hands: Int, unattended: Int = 0, station: KitchenStation? = nil, after: [String] = []) {
        self.id = id
        self.name = name
        self.component = component
        self.handsMinutes = max(0, hands)
        self.unattendedMinutes = max(0, unattended)
        self.station = station
        self.after = after
    }

    /// From the first move to the moment the step is done.
    public var minutes: Int { handsMinutes + unattendedMinutes }
}

/// What the kitchen offers.
public struct Kitchen: Equatable, Sendable {
    public var burners: Int
    public var ovens: Int

    public init(burners: Int = 4, ovens: Int = 1) {
        self.burners = max(0, burners)
        self.ovens = max(0, ovens)
    }

    func capacity(of station: KitchenStation) -> Int {
        switch station {
        case .burner: return burners
        case .oven: return ovens
        }
    }
}

/// Why a dish does not fit its budget.
public enum KitchenLimit: Equatable, Sendable {
    /// The longest chain of dependent steps is longer than the budget;
    /// no amount of parallel work helps.
    case criticalPath
    /// The attended minutes alone exceed the budget: one pair of hands is
    /// not enough.
    case hands
    /// Chain and hands would fit, but steps collide on the hands or the
    /// stations; the dish needs more time than its bounds.
    case packing
}

public enum KitchenSchedulingError: Error, Equatable {
    case duplicateTask(String)
    case unknownDependency(task: String, dependency: String)
    case cycle
    case stationMissing(KitchenStation)
}

/// A step placed on the timeline, in minutes from the start of cooking.
public struct KitchenPlacement: Identifiable, Equatable, Sendable {
    public let task: KitchenTask
    public let start: Int
    public var id: String { task.id }
    public var handsEnd: Int { start + task.handsMinutes }
    public var end: Int { start + task.minutes }
}

public struct KitchenSchedule: Equatable, Sendable {
    public let placements: [KitchenPlacement]
    public let kitchen: Kitchen
    public let budget: Int?
    /// When the last step is done.
    public let makespan: Int
    /// The longest chain of dependent steps, by their full durations.
    public let criticalPathMinutes: Int
    /// The ids on that chain, first to last.
    public let criticalPath: [String]
    /// All attended minutes together.
    public let handsMinutes: Int

    public var fits: Bool { budget.map { makespan <= $0 } ?? true }

    /// Minutes missing to the budget; 0 when the dish fits.
    public var shortfall: Int { budget.map { max(0, makespan - $0) } ?? 0 }

    /// Minutes left over within the budget; 0 when the dish does not fit.
    public var slack: Int { budget.map { max(0, $0 - makespan) } ?? 0 }

    /// The reason the dish does not fit, nil when it does. Where both the
    /// chain and the hands exceed the budget, the larger of the two.
    public var limit: KitchenLimit? {
        guard let budget, makespan > budget else { return nil }
        let chainOver = criticalPathMinutes > budget
        let handsOver = handsMinutes > budget
        switch (chainOver, handsOver) {
        case (true, true): return criticalPathMinutes >= handsMinutes ? .criticalPath : .hands
        case (true, false): return .criticalPath
        case (false, true): return .hands
        case (false, false): return .packing
        }
    }

    /// Minutes in which the hands have nothing to do before the last step
    /// ends — the room for the budget's other demands, or for a drink.
    public var idleHandsMinutes: Int { makespan - handsMinutes }

    public func placement(of id: String) -> KitchenPlacement? {
        placements.first { $0.task.id == id }
    }

    /// How long a finished step waits until the first step that needs it
    /// begins — or until the end, for a step nothing waits for. A pear
    /// glazed in minute 8 and plated in minute 34 waits 26 minutes.
    public func waitingMinutes(of id: String) -> Int? {
        guard let placement = placement(of: id) else { return nil }
        let dependents = placements.filter { $0.task.after.contains(id) }
        let next = dependents.map(\.start).min() ?? makespan
        return max(0, next - placement.end)
    }

    /// The attended minutes per component, largest first — where the
    /// hands' time goes when it is the hands that do not fit.
    public var handsByComponent: [(component: String, minutes: Int)] {
        var minutes = [String: Int]()
        for placement in placements {
            minutes[placement.task.component, default: 0] += placement.task.handsMinutes
        }
        return minutes.map { (component: $0.key, minutes: $0.value) }
            .sorted { $0.minutes != $1.minutes ? $0.minutes > $1.minutes : $0.component < $1.component }
    }

    /// The start of a step on the clock when the dish is to be ready at
    /// `serving`.
    public func startDate(of id: String, serving: Date) -> Date? {
        placement(of: id).map { serving.addingTimeInterval(TimeInterval(($0.start - makespan) * 60)) }
    }

    /// The timeline as text, one line per step in start order, for tests
    /// and for looking at a plan: "  0– 3  ✋ 3   Perlhuhn vorbereiten".
    public var timelineText: String {
        placements.sorted { $0.start != $1.start ? $0.start < $1.start : $0.task.id < $1.task.id }
            .map { placement in
                let task = placement.task
                let hands = task.handsMinutes > 0 ? "✋\(task.handsMinutes)" : "   "
                let station: String
                switch task.station {
                case .burner: station = " 🔥"
                case .oven: station = " ♨︎"
                case nil: station = "   "
                }
                let span = String(format: "%2d–%2d", placement.start, placement.end)
                return "\(span) \(hands.padding(toLength: 4, withPad: " ", startingAt: 0))\(station)  \(task.name)"
            }
            .joined(separator: "\n")
    }
}

public enum KitchenScheduler {

    /// Places the steps forward from minute 0: at every moment the step
    /// with the longest chain still ahead of it goes first, provided the
    /// hands and its station are free. Steps with unattended time are
    /// preferred among equals, so a pot gets going before the knife work.
    /// Throws for duplicate ids, unknown dependencies, a cycle, or a step
    /// that needs a station the kitchen does not have.
    public static func schedule(_ tasks: [KitchenTask], kitchen: Kitchen = Kitchen(),
                                budget: Int? = nil) throws -> KitchenSchedule {
        try checkIDs(tasks)
        let order = try topologicalOrder(tasks)
        for task in tasks {
            if let station = task.station, kitchen.capacity(of: station) == 0 {
                throw KitchenSchedulingError.stationMissing(station)
            }
        }

        // The longest chain from each step to the end, the step included,
        // computed from the last step backwards.
        var tail = [String: Int]()
        var tailNext = [String: String]()
        let dependents = Dictionary(grouping: tasks.flatMap { task in task.after.map { ($0, task.id) } },
                                    by: { $0.0 }).mapValues { $0.map { $0.1 } }
        for task in order.reversed() {
            var best = 0
            var next: String?
            for dependent in dependents[task.id] ?? [] {
                if let length = tail[dependent], length > best || (length == best && (next.map { dependent < $0 } ?? true)) {
                    best = length
                    next = dependent
                }
            }
            tail[task.id] = task.minutes + best
            tailNext[task.id] = next
        }
        let criticalStart = order.max { (tail[$0.id] ?? 0, $1.id) < (tail[$1.id] ?? 0, $0.id) }
        var criticalPath = [String]()
        var cursor = criticalStart?.id
        while let id = cursor {
            criticalPath.append(id)
            cursor = tailNext[id]
        }

        // The simulation: time jumps from event to event; at each, every
        // ready step that can start, starts, best first.
        var placements = [String: KitchenPlacement]()
        var handsFreeAt = 0
        var stationsFreeAt: [KitchenStation: [Int]] = [
            .burner: Array(repeating: 0, count: kitchen.burners),
            .oven: Array(repeating: 0, count: kitchen.ovens)
        ]
        var time = 0
        var remaining = Set(tasks.map(\.id))

        func priority(_ a: KitchenTask, _ b: KitchenTask) -> Bool {
            let ta = tail[a.id] ?? 0, tb = tail[b.id] ?? 0
            if ta != tb { return ta > tb }
            if a.unattendedMinutes != b.unattendedMinutes { return a.unattendedMinutes > b.unattendedMinutes }
            return a.id < b.id
        }

        var guardCounter = 0
        while !remaining.isEmpty {
            guardCounter += 1
            if guardCounter > tasks.count * 4 + 100_000 { throw KitchenSchedulingError.cycle }

            let ready = order.filter { task in
                remaining.contains(task.id)
                    && task.after.allSatisfy { placements[$0].map { $0.end <= time } ?? false }
            }.sorted(by: priority)

            var startedOne = false
            for task in ready {
                if task.handsMinutes > 0, handsFreeAt > time { continue }
                var stationIndex: Int?
                if let station = task.station {
                    guard let index = stationsFreeAt[station]?.firstIndex(where: { $0 <= time }) else { continue }
                    stationIndex = index
                }
                let placement = KitchenPlacement(task: task, start: time)
                placements[task.id] = placement
                remaining.remove(task.id)
                if task.handsMinutes > 0 { handsFreeAt = placement.handsEnd }
                if let station = task.station, let index = stationIndex {
                    stationsFreeAt[station]?[index] = placement.end
                }
                startedOne = true
                // Hands or a station changed; look at the list afresh.
                break
            }
            if startedOne { continue }

            // Nothing can start now: move to the next moment something frees up.
            var events = [Int]()
            if handsFreeAt > time { events.append(handsFreeAt) }
            events += stationsFreeAt.values.flatMap { $0 }.filter { $0 > time }
            events += placements.values.map(\.end).filter { $0 > time }
            guard let next = events.min() else {
                // Only dependencies are open and none ends later: impossible
                // after the cycle check, kept so the loop cannot spin.
                throw KitchenSchedulingError.cycle
            }
            time = next
        }

        let placed = order.compactMap { placements[$0.id] }
        return KitchenSchedule(placements: placed, kitchen: kitchen, budget: budget,
                               makespan: placed.map(\.end).max() ?? 0,
                               criticalPathMinutes: criticalStart.flatMap { tail[$0.id] } ?? 0,
                               criticalPath: criticalPath,
                               handsMinutes: tasks.reduce(0) { $0 + $1.handsMinutes })
    }

    private static func checkIDs(_ tasks: [KitchenTask]) throws {
        var byID = [String: KitchenTask]()
        for task in tasks {
            if byID[task.id] != nil { throw KitchenSchedulingError.duplicateTask(task.id) }
            byID[task.id] = task
        }
        for task in tasks {
            for dependency in task.after where byID[dependency] == nil {
                throw KitchenSchedulingError.unknownDependency(task: task.id, dependency: dependency)
            }
        }
    }

    /// Kahn's algorithm; the input order breaks ties, so the result is
    /// stable for equal recipes.
    private static func topologicalOrder(_ tasks: [KitchenTask]) throws -> [KitchenTask] {
        var open = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, Set($0.after)) })
        var order = [KitchenTask]()
        while order.count < tasks.count {
            guard let next = tasks.first(where: { open[$0.id]?.isEmpty == true }) else {
                throw KitchenSchedulingError.cycle
            }
            order.append(next)
            open[next.id] = nil
            for id in open.keys { open[id]?.remove(next.id) }
        }
        return order
    }
}
