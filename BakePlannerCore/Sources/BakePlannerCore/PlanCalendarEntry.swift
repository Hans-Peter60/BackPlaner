//
//  PlanCalendarEntry.swift
//  BakePlannerCore
//
//  A plan's steps as calendar entries, so the household sees when the
//  oven is taken: one entry per step, from the step's time for as long as
//  the step takes, at least a quarter of an hour so it shows on a day
//  view. The iPhone writes them into the calendar (CalendarExport); what an
//  entry says is decided here, where it can be tested.
//

import Foundation

public struct PlanCalendarEntry: Equatable {
    public let title: String
    public let start: Date
    public let end: Date
    public let notes: String?

    public init(title: String, start: Date, end: Date, notes: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
    }

    /// The shortest an entry is: a step of no length still takes a line in
    /// the calendar.
    public static let minimumMinutes = 15

    /// One entry per step, titled "Rezept: Schritt", for the step's duration
    /// and at least `minimumMinutes`; the plan's end step ("Backende") is
    /// a quarter of an hour.
    public static func entries(for steps: [ScheduledStepData],
                               bundle: Bundle = AppSettings.localizationBundle) -> [PlanCalendarEntry] {
        let notes = String(localized: "Geplant mit BakePlanner.", bundle: bundle)
        return steps
            .sorted { $0.date < $1.date }
            .map { step in
                let minutes = max(step.duration, minimumMinutes)
                return PlanCalendarEntry(title: "\(step.recipeName): \(step.instruction)",
                                         start: step.date,
                                         end: step.date.addingTimeInterval(TimeInterval(minutes * 60)),
                                         notes: notes)
            }
    }
}
