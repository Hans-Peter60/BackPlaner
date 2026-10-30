//
//  PlanTimeline.swift
//  BackPlaner
//
//  The project-plan view of the scheduled steps (the "Timeline" tab): a
//  time scale that stretches short steps to a readable minimum and shrinks
//  a long idle stretch — the overnight rest — to a fixed band, and the
//  lanes drawn on it, one per plan, with a bar per step and a marker for
//  every sub-step that falls inside its parent (a fold during the rest,
//  the turn-down during the bake). Plain values: the vertical layout of an
//  iPhone in portrait and the horizontal one of an iPad use the same
//  arithmetic, and the tests check it without a view.
//

import BakePlannerCore
import CoreGraphics
import Foundation

// MARK: - Scale

/// Maps dates to positions along the time axis. Between two consecutive
/// step boundaries the scale is linear, `pointsPerMinute` wide, but never
/// shorter than `minimumInterval`, so a five-minute step still has room for
/// its text. A stretch without any boundary that is longer than
/// `gapThreshold` keeps `gapEdge` at either end at full scale and collapses
/// the middle to `gapLength`: twelve hours of ripening take as much room as
/// a short step, and a band says what was skipped. A rise of three hours
/// stays at full scale — it is the night that needs collapsing, not every
/// long rest.
struct PlanTimelineScale: Equatable {

    /// A collapsed stretch: what it covers and where it is drawn.
    struct Gap: Equatable {
        let start: Date
        let end: Date
        let position: CGFloat
        let length: CGFloat
    }

    /// A labelled point on the axis. `startsDay` marks the first tick of a
    /// day, which the axis labels with the weekday as well as the time.
    struct Tick: Equatable {
        let date: Date
        let position: CGFloat
        let startsDay: Bool
    }

    let start: Date
    let end: Date
    /// The axis length in points.
    let length: CGFloat
    let gaps: [Gap]
    let ticks: [Tick]

    /// Dates with their positions, sorted; the scale is linear in between.
    private let knots: [(date: Date, position: CGFloat)]

    static func == (lhs: PlanTimelineScale, rhs: PlanTimelineScale) -> Bool {
        lhs.start == rhs.start && lhs.end == rhs.end && lhs.length == rhs.length
            && lhs.gaps == rhs.gaps && lhs.ticks == rhs.ticks
    }

    /// `roomAfter` asks for more than `minimumInterval` after particular
    /// boundaries: a bar whose marker sits at its very start needs a second
    /// line for the marker's label.
    init(boundaries: [Date],
         pointsPerMinute: CGFloat,
         minimumInterval: CGFloat = 26,
         roomAfter: [Date: CGFloat] = [:],
         gapThreshold: TimeInterval = 4 * 3600,
         gapEdge: TimeInterval = 30 * 60,
         gapLength: CGFloat = 44,
         minimumTickSpacing: CGFloat = 40,
         calendar: Calendar = .current) {

        // Whole minutes; two steps a few seconds apart are one boundary.
        let dates = Array(Set(boundaries.map(Self.wholeMinute))).sorted()
        let roomAfter = Dictionary(roomAfter.map { (Self.wholeMinute($0.key), $0.value) }, uniquingKeysWith: max)

        guard let first = dates.first, let last = dates.last else {
            start = Date()
            end = start
            length = 0
            gaps = []
            ticks = []
            knots = []
            return
        }

        var knots: [(date: Date, position: CGFloat)] = [(first, 0)]
        var gaps: [Gap] = []
        var position: CGFloat = 0

        for (from, to) in zip(dates, dates.dropFirst()) {
            let seconds = to.timeIntervalSince(from)
            if seconds > gapThreshold, seconds > 2 * gapEdge {
                // Edge at full scale, then the band, then the other edge.
                let bandStart = from.addingTimeInterval(gapEdge)
                let bandEnd = to.addingTimeInterval(-gapEdge)
                position += CGFloat(gapEdge / 60) * pointsPerMinute
                knots.append((bandStart, position))
                gaps.append(Gap(start: bandStart, end: bandEnd, position: position, length: gapLength))
                position += gapLength
                knots.append((bandEnd, position))
                position += CGFloat(gapEdge / 60) * pointsPerMinute
                knots.append((to, position))
            } else {
                position += max(CGFloat(seconds / 60) * pointsPerMinute, minimumInterval, roomAfter[from] ?? 0)
                knots.append((to, position))
            }
        }

        start = first
        end = last
        length = position
        self.gaps = gaps
        self.knots = knots

        ticks = Self.ticks(from: first, to: last, gaps: gaps, gapEdge: gapEdge, knots: knots,
                           minimumSpacing: minimumTickSpacing, calendar: calendar)
    }

    static func wholeMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded() * 60)
    }

    /// The position of a date; before the start it is 0, after the end the
    /// full length.
    func position(of date: Date) -> CGFloat {
        guard let firstKnot = knots.first, let lastKnot = knots.last else { return 0 }
        if date <= firstKnot.date { return 0 }
        if date >= lastKnot.date { return lastKnot.position }

        // The knot pair the date falls between; linear in between.
        var low = 0
        var high = knots.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if knots[middle].date <= date { low = middle } else { high = middle }
        }
        let (fromDate, fromPosition) = knots[low]
        let (toDate, toPosition) = knots[high]
        let span = toDate.timeIntervalSince(fromDate)
        guard span > 0 else { return fromPosition }
        let fraction = date.timeIntervalSince(fromDate) / span
        return fromPosition + CGFloat(fraction) * (toPosition - fromPosition)
    }

    /// The length between two dates on the axis.
    func length(from: Date, to: Date) -> CGFloat {
        max(0, position(of: to) - position(of: from))
    }

    /// Whether a date lies inside a collapsed band.
    func isInGap(_ date: Date) -> Bool {
        gaps.contains { $0.start < date && date < $0.end }
    }

    /// The axis labels: the start, every resumption after a band, and the
    /// full hours in between — the latter only where they keep
    /// `minimumSpacing` from their neighbours, so a small scale shows every
    /// second or third hour instead of overlapping labels.
    private static func ticks(from start: Date, to end: Date, gaps: [Gap], gapEdge: TimeInterval,
                              knots: [(date: Date, position: CGFloat)],
                              minimumSpacing: CGFloat, calendar: Calendar) -> [Tick] {
        func position(of date: Date) -> CGFloat {
            // The knots are what `position(of:)` uses; duplicated here
            // because the scale is not built yet.
            guard let first = knots.first, let last = knots.last else { return 0 }
            if date <= first.date { return 0 }
            if date >= last.date { return last.position }
            var low = 0, high = knots.count - 1
            while high - low > 1 {
                let middle = (low + high) / 2
                if knots[middle].date <= date { low = middle } else { high = middle }
            }
            let span = knots[high].date.timeIntervalSince(knots[low].date)
            guard span > 0 else { return knots[low].position }
            let fraction = date.timeIntervalSince(knots[low].date) / span
            return knots[low].position + CGFloat(fraction) * (knots[high].position - knots[low].position)
        }

        // Fixed ticks: the start and the step boundary after every band,
        // where the plan resumes. Hour ticks fill in.
        let fixed = ([start] + gaps.map { $0.end.addingTimeInterval(gapEdge) }).map { ($0, position(of: $0)) }
        var hours: [(Date, CGFloat)] = []
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: start)
        components.minute = 0
        var hour = calendar.date(from: components) ?? start
        while hour <= end {
            if hour > start, !gaps.contains(where: { $0.start < hour && hour < $0.end }) {
                hours.append((hour, position(of: hour)))
            }
            guard let next = calendar.date(byAdding: .hour, value: 1, to: hour) else { break }
            hour = next
        }

        var kept: [(Date, CGFloat)] = []
        var hourIndex = 0
        for (fixedIndex, fixedTick) in fixed.enumerated() {
            kept.append(fixedTick)
            let nextFixedPosition = fixedIndex + 1 < fixed.count ? fixed[fixedIndex + 1].1 : CGFloat.infinity
            while hourIndex < hours.count, hours[hourIndex].1 < nextFixedPosition {
                let candidate = hours[hourIndex]
                hourIndex += 1
                let farFromPrevious = candidate.1 - (kept.last?.1 ?? -CGFloat.infinity) >= minimumSpacing
                let farFromNext = nextFixedPosition - candidate.1 >= minimumSpacing
                if farFromPrevious, farFromNext { kept.append(candidate) }
            }
        }

        var ticks: [Tick] = []
        for (date, position) in kept {
            let startsDay = ticks.last.map { !calendar.isDate($0.date, inSameDayAs: date) } ?? true
            ticks.append(Tick(date: date, position: position, startsDay: startsDay))
        }
        return ticks
    }
}

// MARK: - Lanes

/// What a step does, for its colour.
enum PlanTimelineKind: Equatable {
    case mix, rest, fold, shape, oven, bake, other
}

/// One scheduled step, whichever store it came from.
struct PlanTimelineEntry: Identifiable, Equatable {
    let id: AnyHashable
    let recipeName: String
    let planID: UUID?
    let instruction: String
    let step: Double
    let date: Date
    /// Minutes.
    let duration: Int

    var end: Date { date.addingTimeInterval(TimeInterval(duration * 60)) }
    var planKey: PlanKey { PlanKey(recipeName: recipeName, planID: planID) }
}

/// A point on a lane: a sub-step inside its parent's bar, or a step without
/// a duration.
struct PlanTimelineMarker: Identifiable, Equatable {
    let entry: PlanTimelineEntry
    let kind: PlanTimelineKind
    var id: AnyHashable { entry.id }
    var date: Date { entry.date }
}

/// A step with a duration, drawn as long as it lasts. Bars that overlap
/// in time share the lane side by side: `track` says which strip of the
/// lane this bar takes, `trackCount` how many strips its cluster of
/// overlapping bars needs.
struct PlanTimelineBar: Identifiable, Equatable {
    let entry: PlanTimelineEntry
    let kind: PlanTimelineKind
    var markers: [PlanTimelineMarker] = []
    var track = 0
    var trackCount = 1
    var id: AnyHashable { entry.id }
    var start: Date { entry.date }
    var end: Date { entry.end }
}

/// One plan: its bars, loose markers and the finish.
struct PlanTimelineLane: Identifiable, Equatable {
    let id: PlanKey
    let bars: [PlanTimelineBar]
    let markers: [PlanTimelineMarker]
    /// "Backvorgang ist beendet", if the plan has it.
    let finish: Date?
    let start: Date
    let end: Date

    var recipeName: String { id.recipeName }

    /// Every date the scale has to keep apart: bar starts and ends, markers
    /// and the finish.
    var boundaries: [Date] {
        bars.flatMap { [$0.start, $0.end] + $0.markers.map(\.date) } + markers.map(\.date) + [finish].compactMap { $0 }
    }

    /// The starts of bars with a marker in their first minute — the
    /// turn-down as the loaf goes in. Such a bar needs room for the
    /// marker's label under its own first line.
    var startsWithMarker: [Date] {
        bars.filter { bar in bar.markers.contains { abs($0.date.timeIntervalSince(bar.start)) < 60 } }.map(\.start)
    }

    /// One lane per plan, in the order of their first step.
    static func lanes(from entries: [PlanTimelineEntry]) -> [PlanTimelineLane] {
        let sorted = entries.sorted { ($0.date, $0.step) < ($1.date, $1.step) }
        var order: [PlanKey] = []
        var grouped: [PlanKey: [PlanTimelineEntry]] = [:]
        for entry in sorted {
            if grouped[entry.planKey] == nil { order.append(entry.planKey) }
            grouped[entry.planKey, default: []].append(entry)
        }
        return order.compactMap { key in grouped[key].map { lane(key, entries: $0) } }
    }

    /// Whole-numbered steps with a duration become bars; the finish (step
    /// 99) is the lane's end. A sub-step (3.1) that falls inside its
    /// parent's bar (3) and is a moment rather than a task of its own —
    /// the folds of a rest, the turn-down of a bake, the oven switched on
    /// during the final proof, anything without a duration — is a marker
    /// on it. A sub-step with work of its own ("Brühstück herstellen"
    /// while the sourdough ripens) is a bar that runs alongside; one that
    /// does not lie inside its parent is a bar of its own, or a loose
    /// marker when it has no duration. Overlapping bars are then dealt
    /// into tracks.
    static func lane(_ key: PlanKey, entries: [PlanTimelineEntry]) -> PlanTimelineLane {
        var bars: [PlanTimelineBar] = []
        var loose: [PlanTimelineMarker] = []
        var subSteps: [PlanTimelineEntry] = []
        var finish: Date?

        for entry in entries {
            if entry.step >= 99 {
                finish = max(finish ?? entry.date, entry.date)
            } else if entry.step != entry.step.rounded(.down) {
                subSteps.append(entry)
            } else if entry.duration > 0 {
                bars.append(PlanTimelineBar(entry: entry, kind: kind(of: entry)))
            } else {
                loose.append(PlanTimelineMarker(entry: entry, kind: kind(of: entry)))
            }
        }

        for sub in subSteps {
            let subKind = kind(of: sub)
            // The parent is the bar the sub-step falls into: the one with its
            // whole number when that bar runs at the time, else the bar that
            // began last. The generated oven step is numbered after the step
            // before the bake (6.9), which may have ended long before the
            // oven is switched on during the proof; and a recipe may number
            // its bake 7.1, with the turn-down at 7.2.
            let parentStep = sub.step.rounded(.down)
            let containing = bars.indices.filter { bars[$0].start <= sub.date && sub.date < bars[$0].end }
            let parent = containing.first { bars[$0].entry.step == parentStep }
                ?? containing.max { bars[$0].start < bars[$1].start }
            if let parent, sub.duration == 0 || subKind == .fold || subKind == .oven {
                bars[parent].markers.append(PlanTimelineMarker(entry: sub, kind: subKind))
            } else if sub.duration > 0 {
                bars.append(PlanTimelineBar(entry: sub, kind: subKind))
            } else {
                loose.append(PlanTimelineMarker(entry: sub, kind: subKind))
            }
        }
        bars.sort { ($0.start, $0.entry.step) < ($1.start, $1.entry.step) }
        assignTracks(&bars)

        let dates = bars.flatMap { [$0.start, $0.end] } + loose.map(\.date) + [finish].compactMap { $0 }
        let start = dates.min() ?? Date()
        let end = dates.max() ?? start
        return PlanTimelineLane(id: key, bars: bars, markers: loose, finish: finish, start: start, end: end)
    }

    /// Deals overlapping bars into tracks. Bars are visited in order of
    /// their start; a bar that begins after every bar so far has ended
    /// opens a new cluster. Within a cluster each bar takes the first track
    /// that is free when it starts, and every bar of the cluster is told
    /// how many tracks the cluster uses. A bar that overlaps nothing keeps
    /// the whole lane.
    private static func assignTracks(_ bars: inout [PlanTimelineBar]) {
        var clusterStart = 0
        var clusterEnd: Date?
        var trackEnds: [Date] = []

        for index in bars.indices {
            let bar = bars[index]
            if let end = clusterEnd, bar.start >= end {
                for member in clusterStart..<index { bars[member].trackCount = trackEnds.count }
                clusterStart = index
                clusterEnd = nil
                trackEnds = []
            }
            if let track = trackEnds.firstIndex(where: { $0 <= bar.start }) {
                trackEnds[track] = bar.end
                bars[index].track = track
            } else {
                trackEnds.append(bar.end)
                bars[index].track = trackEnds.count - 1
            }
            clusterEnd = max(clusterEnd ?? bar.end, bar.end)
        }
        for member in clusterStart..<bars.count { bars[member].trackCount = max(1, trackEnds.count) }
    }

    // MARK: Kind

    private static let foldWords = ["falten", "dehnen", "fold", "rabat", "stretch"]
    private static let shapeWords = ["formen", "wirken", "aufarbeiten", "shape", "shaping", "faconn", "bouler", "preshape"]
    private static let restWords = ["ruhen", "reifen", "gehen lassen", "gare", "lagern", "fermentier", "quellen", "autolyse",
                                    "rest", "rise", "proof", "ferment", "bulk", "pousse", "lever", "repos", "pointage", "appret"]
    private static let mixWords = ["mischen", "kneten", "herstellen", "verruhren", "ansetzen", "zubereiten", "vermengen",
                                   "mix", "knead", "combine", "prepare", "petrir", "melanger", "preparer", "incorporer"]

    static func kind(of entry: PlanTimelineEntry) -> PlanTimelineKind {
        kind(of: entry.instruction, duration: entry.duration)
    }

    static func kind(of instruction: String, duration: Int) -> PlanTimelineKind {
        let text = instruction.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                       locale: Locale(identifier: "de_DE"))
        if BakePlanValidator.isPreheatInstruction(instruction)
            || BakePlan.isTurnDownInstruction(instruction)
            || BakePlan.isSteamReleaseInstruction(instruction) {
            return .oven
        }
        if BakePlanValidator.isBakingStartInstruction(instruction) { return .bake }
        if foldWords.contains(where: text.contains) { return .fold }
        if shapeWords.contains(where: text.contains) { return .shape }
        // A long step that mixes and then ripens is a rest; a short one is
        // the mixing.
        let rests = restWords.contains(where: text.contains)
        let mixes = mixWords.contains(where: text.contains)
        if rests, mixes { return duration >= 60 ? .rest : .mix }
        if mixes { return .mix }
        if rests { return .rest }
        return .other
    }
}
