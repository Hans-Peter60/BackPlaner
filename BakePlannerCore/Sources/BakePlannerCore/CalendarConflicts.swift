//
//  CalendarConflicts.swift
//  BakePlannerCore
//
//  Where a plan collides with the baker's own calendar: the moments the
//  plan needs them in the kitchen — hands in the dough, the oven switched
//  on, the bread put in and taken out — against the appointments of the
//  day. Reading the calendar is the app's job; the comparison lives here.
//

import Foundation

public struct CalendarEvent: Equatable {
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool

    public init(title: String, start: Date, end: Date, isAllDay: Bool = false) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }
}

/// One appointment that falls into a moment the plan needs the baker.
public struct CalendarConflict: Equatable, Identifiable {
    public let step: String
    public let stepDate: Date
    public let event: CalendarEvent
    public var id: String { "\(stepDate.timeIntervalSinceReferenceDate)-\(event.title)-\(event.start.timeIntervalSinceReferenceDate)" }
}

public enum CalendarConflicts {

    /// Minutes the baker is needed when the oven goes on, the bread goes in
    /// and comes out.
    public static let ovenMomentMinutes = 10

    /// When the plan needs the baker: the hands-on work of the recipe's
    /// steps (as the baking day counts it), the oven being switched on,
    /// and the start and end of the bake. Rests and the plan's end are none.
    public static func presenceIntervals(of plan: BakePlan) -> [(step: String, interval: DateInterval)] {
        var intervals: [(String, DateInterval)] = []
        let moment = TimeInterval(ovenMomentMinutes * 60)
        for step in plan.scheduledSteps {
            let date = plan.date(of: step)
            if let work = BakingDayOptimizer.workInterval(instruction: step.instruction, duration: step.duration, date: date) {
                intervals.append((step.instruction, work))
            } else if let bake = plan.bakingStep, step == bake {
                intervals.append((step.instruction, DateInterval(start: date, duration: moment)))
                if step.duration > ovenMomentMinutes {
                    let end = date.addingTimeInterval(TimeInterval(step.duration * 60))
                    intervals.append((step.instruction, DateInterval(start: end.addingTimeInterval(-moment), duration: moment)))
                }
            } else if let preheat = plan.explicitPreheatStep, step == preheat {
                intervals.append((step.instruction, DateInterval(start: date, duration: moment)))
            }
        }
        if let oven = plan.generatedOvenStep {
            intervals.append((oven.instruction, DateInterval(start: plan.date(of: oven), duration: moment)))
        }
        return intervals.sorted { $0.1.start < $1.1.start }
    }

    /// The appointments that overlap a presence interval, each pair once,
    /// in the plan's order. All-day events are no appointments.
    public static func find(in plan: BakePlan, events: [CalendarEvent]) -> [CalendarConflict] {
        let timed = events.filter { !$0.isAllDay && $0.end > $0.start }
        var found: [CalendarConflict] = []
        for (step, interval) in presenceIntervals(of: plan) {
            for event in timed where event.start < interval.end && interval.start < event.end {
                let conflict = CalendarConflict(step: step, stepDate: interval.start, event: event)
                if !found.contains(conflict) {
                    found.append(conflict)
                }
            }
        }
        return found
    }
}
