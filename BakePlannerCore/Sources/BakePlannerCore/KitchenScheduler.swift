//
//  KitchenScheduler.swift
//  BakePlannerCore
//
//  One cook, a few burners, one oven and a time budget: the order in which
//  the work of a dish gets done so that everything is ready together. A
//  step binds the cook's hands for a while ("Zwiebeln würfeln", 2 min) and
//  may then run on its own ("Graupen 25 Minuten kochen") while it keeps a
//  burner or the oven — an oven takes several steps at once, but only at
//  one temperature; a step may have to wait for others ("Füllung
//  mischen" needs the barley, the meat and the mushrooms). The scheduler
//  places every step forward from minute 0 — hands never on two things,
//  never more pans than burners — and says whether the dish fits the budget
//  and, if not, why: the longest chain of steps is too long, or the hands
//  alone have more to do than the budget allows.
//
//  A step may say how long its result keeps (`maxWait`): the seared breast
//  has to be turned at once, rested meat sliced within a few minutes, a
//  sauce can stand ten. The scheduler keeps the hands free for such a
//  follow-up — no knife work that would run past the moment — and reports
//  where it still could not keep the time, and which finished parts wait
//  long enough to need keeping warm.
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
    /// How many minutes the finished step may wait before a step that
    /// needs it begins: 0 for "wenden" after searing, a few for rested
    /// meat, ten for a sauce kept warm. Nil when the result keeps.
    public let maxWait: Int?
    /// The span the recipe allows the unattended part ("20–25 Minuten
    /// backen"); `unattendedMinutes` is the value planned with and lies
    /// within it. Nil when the recipe names one time.
    public let unattendedWindow: ClosedRange<Int>?
    /// For a step in the oven, the temperature it needs in °C. An oven
    /// holds several steps at once, but only at one temperature; a step
    /// without one goes in at whatever the oven is at.
    public let ovenTemperature: Int?

    public init(id: String, name: String, component: String = "",
                hands: Int, unattended: Int = 0, station: KitchenStation? = nil, after: [String] = [],
                maxWait: Int? = nil, window: ClosedRange<Int>? = nil, ovenTemperature: Int? = nil) {
        self.id = id
        self.name = name
        self.component = component
        self.handsMinutes = max(0, hands)
        let window = window.map { max(0, $0.lowerBound)...max(0, $0.lowerBound, $0.upperBound) }
        self.unattendedWindow = window
        self.unattendedMinutes = window.map { min(max(max(0, unattended), $0.lowerBound), $0.upperBound) } ?? max(0, unattended)
        self.station = station
        self.after = after
        self.maxWait = maxWait.map { max(0, $0) }
        self.ovenTemperature = station == .oven ? ovenTemperature : nil
    }

    /// The same step with its unattended part set to `minutes`, within
    /// the window.
    public func shortened(to minutes: Int) -> KitchenTask {
        KitchenTask(id: id, name: name, component: component, hands: handsMinutes, unattended: minutes,
                    station: station, after: after, maxWait: maxWait, window: unattendedWindow,
                    ovenTemperature: ovenTemperature)
    }

    /// Whether two steps can be in one oven at the same time.
    public func sharesOven(with other: KitchenTask) -> Bool {
        guard let mine = ovenTemperature, let theirs = other.ovenTemperature else { return true }
        return mine == theirs
    }

    /// How far the unattended part can still be cut within the window.
    public var reducibleMinutes: Int {
        unattendedWindow.map { max(0, unattendedMinutes - $0.lowerBound) } ?? 0
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

/// A follow-up that began later than its predecessor's `maxWait` allowed.
public struct KitchenLateFollowUp: Equatable, Sendable {
    public let task: String
    public let after: String
    /// Minutes beyond the allowed wait.
    public let minutes: Int
}

/// A finished step that waits for the step that needs it.
public struct KitchenWait: Equatable, Sendable {
    public let task: String
    public let minutes: Int
}

/// A step's unattended part cut within its window to fit the budget.
public struct KitchenShortening: Equatable, Sendable {
    public let task: String
    public let from: Int
    public let to: Int
}

/// A dish fitted into its budget by cutting windowed steps.
public struct KitchenFit: Equatable, Sendable {
    /// The plan with the cuts applied; the nominal plan when none helped.
    public let schedule: KitchenSchedule
    public let shortenings: [KitchenShortening]
}

/// A step placed on the timeline, in minutes from the start of cooking.
public struct KitchenPlacement: Identifiable, Equatable, Sendable {
    public let task: KitchenTask
    public let start: Int
    /// When the hands are free again; as planned, or as it actually went.
    public let handsEnd: Int
    /// When the step is done; as planned, or as it actually went.
    public let end: Int
    public var id: String { task.id }

    /// The step as planned: hands first, then the unattended part.
    public init(task: KitchenTask, start: Int) {
        self.task = task
        self.start = start
        self.handsEnd = start + task.handsMinutes
        self.end = start + task.minutes
    }

    /// The step as it went while cooking.
    public init(task: KitchenTask, start: Int, handsEnd: Int, end: Int) {
        self.task = task
        self.start = start
        self.handsEnd = max(start, handsEnd)
        self.end = max(self.handsEnd, end)
    }
}

/// Where the cooking stands: the minute on the clock and the steps the
/// cook has ticked off, with the minute each was done.
public struct KitchenProgress: Equatable, Sendable {
    public var now: Int
    public var finished: [String: Int]

    public init(now: Int, finished: [String: Int] = [:]) {
        self.now = max(0, now)
        self.finished = finished
    }
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

    /// Follow-ups the plan could not place within their predecessor's
    /// `maxWait`: another predecessor was still running, or a station was
    /// taken. Empty when every "sofort" was kept.
    public var lateFollowUps: [KitchenLateFollowUp] {
        placements.flatMap { placement -> [KitchenLateFollowUp] in
            placement.task.after.compactMap { id -> KitchenLateFollowUp? in
                guard let before = self.placement(of: id), let allowed = before.task.maxWait else { return nil }
                let late = placement.start - before.end - allowed
                return late > 0 ? KitchenLateFollowUp(task: placement.task.id, after: id, minutes: late) : nil
            }
        }
    }

    /// Finished parts that wait at least `minutes` for the step that needs
    /// them — the sauce done in minute 16 and plated in minute 31 wants
    /// keeping warm. Longest wait first.
    public func waits(atLeast minutes: Int) -> [KitchenWait] {
        placements.compactMap { placement -> KitchenWait? in
            guard let wait = waitingMinutes(of: placement.task.id), wait >= minutes else { return nil }
            return KitchenWait(task: placement.task.id, minutes: wait)
        }
        .sorted { $0.minutes != $1.minutes ? $0.minutes > $1.minutes : $0.task < $1.task }
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
    ///
    /// Once a step with a `maxWait` has started, its follow-ups have a
    /// moment by which they must begin; until then no other hands-on work
    /// may start that would run past that moment — except work the
    /// follow-up itself still waits for. A moment that passes unmet stops
    /// holding the hands and shows up in `lateFollowUps`.
    ///
    /// Throws for duplicate ids, unknown dependencies, a cycle, or a step
    /// that needs a station the kitchen does not have.
    public static func schedule(_ tasks: [KitchenTask], kitchen: Kitchen = Kitchen(),
                                budget: Int? = nil) throws -> KitchenSchedule {
        try schedule(tasks, kitchen: kitchen, budget: budget, fixed: [], from: 0)
    }

    /// The dish fitted into `budget` by cutting the unattended parts of
    /// steps with a window, shortest first where it counts: a step on the
    /// longest chain, else — when steps merely collide — any. Cutting goes
    /// no further than the budget needs or the windows allow; the hands'
    /// minutes cannot be cut, so a dish the hands do not fit stays as it is.
    public static func fit(_ tasks: [KitchenTask], kitchen: Kitchen = Kitchen(), budget: Int) throws -> KitchenFit {
        var current = tasks
        var cuts = [String: KitchenShortening]()
        var schedule = try self.schedule(current, kitchen: kitchen, budget: budget)
        for _ in 0..<(tasks.count * 4 + 1) {
            guard !schedule.fits, schedule.limit != .hands else { break }
            let onChain = Set(schedule.criticalPath)
            let candidates = current.filter { $0.reducibleMinutes > 0 }
            guard let pick = candidates.filter({ onChain.contains($0.id) }).max(by: { $0.reducibleMinutes < $1.reducibleMinutes })
                    ?? candidates.max(by: { $0.reducibleMinutes < $1.reducibleMinutes }) else { break }
            let cut = min(pick.reducibleMinutes, max(1, schedule.shortfall))
            let shortened = pick.shortened(to: pick.unattendedMinutes - cut)
            current = current.map { $0.id == pick.id ? shortened : $0 }
            let original = tasks.first { $0.id == pick.id }?.unattendedMinutes ?? pick.unattendedMinutes
            cuts[pick.id] = KitchenShortening(task: pick.id, from: original, to: shortened.unattendedMinutes)
            schedule = try self.schedule(current, kitchen: kitchen, budget: budget)
        }
        return KitchenFit(schedule: schedule, shortenings: tasks.compactMap { cuts[$0.id] })
    }

    /// The plan continued from the middle of cooking. Steps the cook has
    /// ticked off keep their start and end when they did; a step that is
    /// running keeps its start — a hands-only step not yet ticked off holds
    /// the hands until it is, a step with an unattended part ends when it
    /// was planned to. Everything not yet begun is placed afresh from
    /// `progress.now`, around what is running, so a pot that boiled early
    /// pulls its follow-ups forward and a chopping that took longer pushes
    /// them back.
    public static func replan(_ tasks: [KitchenTask], kitchen: Kitchen = Kitchen(), budget: Int? = nil,
                              previous: KitchenSchedule, progress: KitchenProgress) throws -> KitchenSchedule {
        let now = progress.now
        var fixed = [KitchenPlacement]()
        var fixedByID = [String: KitchenPlacement]()
        /// Whether the hands were on a fixed step at `minute`.
        func handsTaken(at minute: Int) -> Bool {
            fixed.contains { $0.task.handsMinutes > 0 && $0.start <= minute && minute < $0.handsEnd }
        }
        // What was ticked off is a fact and comes first. Then, in planned
        // order, a step counts as begun only when what it waits for had
        // ended and the hands were free by then: behind an overdue chopping
        // nothing else has started, whatever the plan said.
        for placement in previous.placements {
            guard let done = progress.finished[placement.task.id] else { continue }
            let task = placement.task
            let start = min(placement.start, done)
            let handsEnd = task.unattendedMinutes == 0 ? done : min(placement.handsEnd, done)
            let actual = KitchenPlacement(task: task, start: start, handsEnd: handsEnd, end: done)
            fixed.append(actual)
            fixedByID[task.id] = actual
        }
        for placement in previous.placements.sorted(by: { ($0.start, $0.task.id) < ($1.start, $1.task.id) })
        where progress.finished[placement.task.id] == nil {
            let task = placement.task
            var actual: KitchenPlacement?
            if placement.start < now {
                let dependenciesMet = task.after.allSatisfy { id in fixedByID[id].map { $0.end <= placement.start } ?? false }
                let handsFree = task.handsMinutes == 0 || !handsTaken(at: placement.start)
                if dependenciesMet && handsFree {
                    // From its start with the task's own durations, not the
                    // placement's: a tick taken back leaves the placement
                    // with the tick's end.
                    if task.unattendedMinutes == 0 && task.handsMinutes > 0 {
                        // Still in the cook's hands until ticked off; overdue,
                        // it is taken to need another minute, and so on.
                        let end = max(placement.start + task.handsMinutes, now + 1)
                        actual = KitchenPlacement(task: task, start: placement.start, handsEnd: end, end: end)
                    } else if let window = task.unattendedWindow, placement.start + task.minutes <= now {
                        // Past its planned end without a tick, a step with a
                        // window is taken to go on, a minute at a time, until
                        // the window's end — then it is done by the clock.
                        let planned = KitchenPlacement(task: task, start: placement.start)
                        let latest = placement.start + task.handsMinutes + window.upperBound
                        let end = min(max(planned.end, now + 1), latest)
                        actual = KitchenPlacement(task: task, start: placement.start, handsEnd: planned.handsEnd, end: end)
                    } else {
                        actual = KitchenPlacement(task: task, start: placement.start)
                    }
                }
            }
            if let actual {
                fixed.append(actual)
                fixedByID[task.id] = actual
            }
        }
        return try schedule(tasks, kitchen: kitchen, budget: budget, fixed: fixed, from: now)
    }

    private static func schedule(_ tasks: [KitchenTask], kitchen: Kitchen, budget: Int?,
                                 fixed: [KitchenPlacement], from startTime: Int) throws -> KitchenSchedule {
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

        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        // Every step a task waits for, directly or further back.
        var ancestors = [String: Set<String>]()
        for task in order {
            var all = Set(task.after)
            for id in task.after { all.formUnion(ancestors[id] ?? []) }
            ancestors[task.id] = all
        }

        func priority(_ a: KitchenTask, _ b: KitchenTask) -> Bool {
            // Work without hands never collides and may set a moment for a
            // follow-up, so it goes first; then the longest chain ahead.
            if (a.handsMinutes == 0) != (b.handsMinutes == 0) { return a.handsMinutes == 0 }
            let ta = tail[a.id] ?? 0, tb = tail[b.id] ?? 0
            if ta != tb { return ta > tb }
            if a.unattendedMinutes != b.unattendedMinutes { return a.unattendedMinutes > b.unattendedMinutes }
            return a.id < b.id
        }

        func schedule(placements: [KitchenPlacement]) -> KitchenSchedule {
            KitchenSchedule(placements: placements, kitchen: kitchen, budget: budget,
                            makespan: placements.map(\.end).max() ?? 0,
                            criticalPathMinutes: criticalStart.flatMap { tail[$0.id] } ?? 0,
                            criticalPath: criticalPath,
                            handsMinutes: tasks.reduce(0) { $0 + $1.handsMinutes })
        }

        // A step whose result keeps only so long should not be done long
        // before the step that needs it — the sauce's finish not twenty
        // minutes before the skin leaves the oven. The forward placement
        // cannot know that in advance, so it runs again with the late
        // predecessors held back by the minutes their follow-up was late,
        // until every moment is kept or holding back changes nothing.
        let fixedIDs = Set(fixed.map(\.task.id))
        var notBefore = [String: Int]()
        var best: KitchenSchedule?
        for _ in 0..<(tasks.count + 1) {
            let attempt = schedule(placements: try place(order, notBefore: notBefore))
            let lateness = attempt.lateFollowUps.reduce(0) { $0 + $1.minutes }
            if let current = best {
                let currentLateness = current.lateFollowUps.reduce(0) { $0 + $1.minutes }
                // A late minute weighs as much as a plan minute: holding
                // back is worth it only while it saves more freshness
                // than it costs in time.
                if (lateness + attempt.makespan, lateness) < (currentLateness + current.makespan, currentLateness) {
                    best = attempt
                }
            } else {
                best = attempt
            }
            if lateness == 0 { break }
            var changed = false
            for late in attempt.lateFollowUps where !fixedIDs.contains(late.after) {
                guard let start = attempt.placement(of: late.after)?.start else { continue }
                let held = start + late.minutes
                if held > notBefore[late.after] ?? 0 {
                    notBefore[late.after] = held
                    changed = true
                }
            }
            if !changed { break }
        }
        return best ?? schedule(placements: [])

        /// The simulation: time jumps from event to event; at each, every
        /// ready step that can start, starts, best first. A step in
        /// `notBefore` waits for its minute.
        func place(_ order: [KitchenTask], notBefore: [String: Int]) throws -> [KitchenPlacement] {
        var placements = [String: KitchenPlacement]()
        var handsFreeAt = startTime
        var burnersFreeAt = Array(repeating: startTime, count: kitchen.burners)
        // Each oven with what is in it; several steps share an oven at one
        // temperature.
        var ovenLoads = Array(repeating: [KitchenPlacement](), count: kitchen.ovens)
        var time = startTime
        var remaining = Set(tasks.map(\.id)).subtracting(fixedIDs)

        /// The oven `task` can go into at `time`: one already at its
        /// temperature first, else an empty one.
        func ovenIndex(for task: KitchenTask, at time: Int) -> Int? {
            var empty: Int?
            for (index, load) in ovenLoads.enumerated() {
                let running = load.filter { $0.end > time }
                if running.isEmpty {
                    if empty == nil { empty = index }
                } else if running.allSatisfy({ $0.task.sharesOven(with: task) }) {
                    return index
                }
            }
            return empty
        }

        // What has happened or is running occupies the hands and the
        // stations as it does, not as it was planned.
        for placement in fixed {
            placements[placement.task.id] = placement
            if placement.task.handsMinutes > 0 { handsFreeAt = max(handsFreeAt, placement.handsEnd) }
            guard placement.end > time else { continue }
            switch placement.task.station {
            case .burner:
                if let slot = burnersFreeAt.indices.min(by: { burnersFreeAt[$0] < burnersFreeAt[$1] }) {
                    burnersFreeAt[slot] = max(burnersFreeAt[slot], placement.end)
                }
            case .oven:
                if !ovenLoads.isEmpty {
                    ovenLoads[ovenIndex(for: placement.task, at: time) ?? 0].append(placement)
                }
            case nil:
                break
            }
        }

        /// The unstarted steps that have to begin by a moment because a
        /// predecessor with a `maxWait` has started, with that moment —
        /// while it has not passed.
        func deadlines() -> [String: Int] {
            var result = [String: Int]()
            for id in remaining {
                guard let task = taskByID[id] else { continue }
                let moments = task.after.compactMap { before -> Int? in
                    guard let placement = placements[before], let allowed = placement.task.maxWait else { return nil }
                    return placement.end + allowed
                }
                if let moment = moments.min(), moment >= time { result[id] = moment }
            }
            return result
        }

        var guardCounter = 0
        while !remaining.isEmpty {
            guardCounter += 1
            if guardCounter > tasks.count * 4 + 100_000 { throw KitchenSchedulingError.cycle }

            let ready = order.filter { task in
                remaining.contains(task.id)
                    && (notBefore[task.id] ?? 0) <= time
                    && task.after.allSatisfy { placements[$0].map { $0.end <= time } ?? false }
            }.sorted(by: priority)

            let due = deadlines()
            var startedOne = false
            for task in ready {
                if task.handsMinutes > 0, handsFreeAt > time { continue }
                // Hands-on work may not run past the moment a follow-up is
                // due, unless the follow-up is this step or waits for it.
                if task.handsMinutes > 0, due.contains(where: { urgent, moment in
                    urgent != task.id && !(ancestors[urgent]?.contains(task.id) ?? false) && time + task.handsMinutes > moment
                }) { continue }
                var stationIndex: Int?
                switch task.station {
                case .burner:
                    guard let index = burnersFreeAt.firstIndex(where: { $0 <= time }) else { continue }
                    stationIndex = index
                case .oven:
                    guard let index = ovenIndex(for: task, at: time) else { continue }
                    stationIndex = index
                case nil:
                    break
                }
                let placement = KitchenPlacement(task: task, start: time)
                placements[task.id] = placement
                remaining.remove(task.id)
                if task.handsMinutes > 0 { handsFreeAt = placement.handsEnd }
                switch task.station {
                case .burner: if let index = stationIndex { burnersFreeAt[index] = placement.end }
                case .oven: if let index = stationIndex { ovenLoads[index].append(placement) }
                case nil: break
                }
                startedOne = true
                // Hands or a station changed; look at the list afresh.
                break
            }
            if startedOne { continue }

            // Nothing can start now: move to the next moment something frees up.
            var events = [Int]()
            if handsFreeAt > time { events.append(handsFreeAt) }
            events += burnersFreeAt.filter { $0 > time }
            events += placements.values.map(\.end).filter { $0 > time }
            // A moment that passes frees the hands again.
            events += due.values.map { $0 + 1 }
            events += notBefore.values.filter { $0 > time }
            guard let next = events.min() else {
                // Only dependencies are open and none ends later: impossible
                // after the cycle check, kept so the loop cannot spin.
                throw KitchenSchedulingError.cycle
            }
            time = next
        }

        return order.compactMap { placements[$0.id] }
        }
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
