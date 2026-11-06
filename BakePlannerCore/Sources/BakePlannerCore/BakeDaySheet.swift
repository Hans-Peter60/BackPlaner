//
//  BakeDaySheet.swift
//  BakePlannerCore
//
//  The "Backtag-Zettel": every scheduled step of the plans, day by day,
//  with time, recipe, duration and the ingredients a step mixes — the
//  sheet that hangs in the kitchen on a baking day with several loaves.
//  Plain strings, so the iPhone's PDF renderer only has to lay them out
//  (RecipePDFRenderer), and the grouping can be tested here.
//

import Foundation

public struct BakeDaySheet: Sendable, Equatable {

    public struct Row: Sendable, Equatable {
        /// "04:25"
        public let time: String
        public let recipeName: String
        public let instruction: String
        /// "1h 15m", empty for a step of no length.
        public let duration: String
        /// The component the step mixes, with its ingredient lines at the
        /// plan's amount; nil for every other step.
        public let componentName: String?
        public let ingredientLines: [String]

        public init(time: String, recipeName: String, instruction: String, duration: String,
                    componentName: String? = nil, ingredientLines: [String] = []) {
            self.time = time
            self.recipeName = recipeName
            self.instruction = instruction
            self.duration = duration
            self.componentName = componentName
            self.ingredientLines = ingredientLines
        }
    }

    public struct Day: Sendable, Equatable {
        /// "Samstag, 7. November 2026"
        public let title: String
        public let rows: [Row]

        public init(title: String, rows: [Row]) {
            self.title = title
            self.rows = rows
        }
    }

    /// "Backtag-Zettel"
    public let title: String
    /// "Stand: 6.11.2026, 17:30"
    public let subtitle: String
    public let days: [Day]

    public init(title: String, subtitle: String, days: [Day]) {
        self.title = title
        self.subtitle = subtitle
        self.days = days
    }

    /// The sheet for `steps`, grouped by calendar day and sorted by time.
    /// `ingredients` gives the component a step mixes with its lines, or
    /// nil; the caller knows the recipes.
    public init(steps: [ScheduledStepData],
                ingredients: (ScheduledStepData) -> (name: String, lines: [String])?,
                locale: Locale = AppSettings.locale,
                calendar: Calendar = .current,
                now: Date = Date(),
                bundle: Bundle = AppSettings.localizationBundle) {
        let sorted = steps.sorted { ($0.date, $0.step) < ($1.date, $1.step) }
        // The styles follow the calendar given, not the device's: the tests
        // run in Berlin whatever the machine's time zone.
        var dayStyle = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).year().locale(locale)
        dayStyle.calendar = calendar
        dayStyle.timeZone = calendar.timeZone
        var timeStyle = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        timeStyle.calendar = calendar
        timeStyle.timeZone = calendar.timeZone
        var standStyle = Date.FormatStyle.dateTime.day().month().year().hour().minute().locale(locale)
        standStyle.calendar = calendar
        standStyle.timeZone = calendar.timeZone
        var days: [Day] = []
        var currentDay: Date?
        var rows: [Row] = []

        func flush() {
            if let day = currentDay, !rows.isEmpty {
                days.append(Day(title: day.formatted(dayStyle), rows: rows))
            }
            rows = []
        }

        for step in sorted {
            let day = calendar.startOfDay(for: step.date)
            if day != currentDay {
                flush()
                currentDay = day
            }
            let component = ingredients(step)
            rows.append(Row(time: step.date.formatted(timeStyle),
                            recipeName: step.recipeName,
                            instruction: step.instruction,
                            duration: step.duration > 0 ? Rational.displayHoursMinutes(step.duration) : "",
                            componentName: component?.name,
                            ingredientLines: component?.lines ?? []))
        }
        flush()

        let stand = now.formatted(standStyle)
        self.init(title: String(localized: "Backtag-Zettel", bundle: bundle),
                  subtitle: String(localized: "Stand: \(stand)", bundle: bundle),
                  days: days)
    }
}
