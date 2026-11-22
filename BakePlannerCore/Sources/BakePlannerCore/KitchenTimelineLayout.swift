//
//  KitchenTimelineLayout.swift
//  BakePlannerCore
//
//  A CookPlanner plan laid out as a timeline: one lane per component, a bar
//  per step from its start to its end. Steps of one component that run at
//  the same time — the sauce reducing while the shallots are cut — share
//  the lane side by side: each bar gets a track within the group of bars
//  that overlap it, so a lone bar keeps the whole width.
//

import Foundation

public struct KitchenTimelineLayout: Equatable, Sendable {

    public struct Bar: Identifiable, Equatable, Sendable {
        public let placement: KitchenPlacement
        /// Its column within the lane, from 0.
        public let track: Int
        /// How many columns the overlapping group it belongs to needs.
        public let tracks: Int
        public var id: String { placement.id }
    }

    public struct Lane: Identifiable, Equatable, Sendable {
        /// The component; empty for the steps without one.
        public let component: String
        public let bars: [Bar]
        public var id: String { component }
    }

    public let lanes: [Lane]
    /// The plan's length in minutes, the end of the time axis.
    public let makespan: Int

    /// The lanes in the dish's order of components, then any the plan has
    /// beyond them, then the steps without a component.
    public init(schedule: KitchenSchedule, components: [String]) {
        var order = components
        for placement in schedule.placements where !order.contains(placement.task.component) {
            if !placement.task.component.isEmpty { order.append(placement.task.component) }
        }
        if schedule.placements.contains(where: { $0.task.component.isEmpty }) { order.append("") }
        lanes = order.compactMap { component in
            let placements = schedule.placements.filter { $0.task.component == component }
            return placements.isEmpty ? nil : Lane(component: component, bars: Self.bars(for: placements))
        }
        makespan = schedule.makespan
    }

    /// Tracks by first fit, groups by overlap: a group ends where no bar of
    /// it reaches past the next start.
    static func bars(for placements: [KitchenPlacement]) -> [Bar] {
        let sorted = placements.sorted { ($0.start, -$0.end, $0.id) < ($1.start, -$1.end, $1.id) }
        var result: [Bar] = []
        var group: [(placement: KitchenPlacement, track: Int)] = []
        var trackEnds: [Int] = []
        var groupEnd = Int.min

        func closeGroup() {
            let count = max(1, trackEnds.count)
            result += group.map { Bar(placement: $0.placement, track: $0.track, tracks: count) }
            group = []
            trackEnds = []
        }

        for placement in sorted {
            // A bar of no length still needs a minute to be seen.
            let end = max(placement.end, placement.start + 1)
            if !group.isEmpty && placement.start >= groupEnd { closeGroup() }
            if let free = trackEnds.firstIndex(where: { $0 <= placement.start }) {
                trackEnds[free] = end
                group.append((placement, free))
            } else {
                trackEnds.append(end)
                group.append((placement, trackEnds.count - 1))
            }
            groupEnd = group.count == 1 ? end : max(groupEnd, end)
        }
        if !group.isEmpty { closeGroup() }
        return result
    }

    /// The minutes the axis labels: every `step` minutes, and the end.
    public func ticks(every step: Int) -> [Int] {
        guard step > 0 else { return [0, makespan] }
        var ticks = Array(stride(from: 0, through: makespan, by: step))
        if ticks.last != makespan { ticks.append(makespan) }
        return ticks
    }
}
