//
//  KitchenPlanSheet.swift
//  BakePlannerCore
//
//  What a printed plan of a CookPlanner dish says, apart from how it is
//  drawn: the steps in the order they begin, numbered, each with its full
//  text, component, hands-on and unattended minutes, station and the
//  ingredients it needs; the times either as clock times from a chosen
//  start or as minutes from 0; and the ingredients by component. The app
//  draws it as a PDF (timeline, table, ingredient list).
//

import Foundation

public struct KitchenPlanSheet: Equatable, Sendable {

    public struct Step: Equatable, Sendable, Identifiable {
        /// 1, 2, 3 … in the order the steps begin; the timeline's bars carry it.
        public let number: Int
        public let taskID: String
        public let name: String
        public let component: String
        public let start: Int
        public let end: Int
        /// "18:12" from a start time, "12′" without.
        public let startText: String
        public let endText: String
        public let handsMinutes: Int
        public let unattendedMinutes: Int
        public let station: KitchenStation?
        public let ovenTemperature: Int?
        /// "200 g Kräuterseitlinge", as the shopping list words them.
        public let ingredients: [String]
        public var id: String { taskID }
    }

    public let title: String
    public let servings: Int?
    public let steps: [Step]
    /// The plan's length in minutes.
    public let minutes: Int
    /// The start and the finish as clock times, nil without a start.
    public let startText: String?
    public let finishText: String?
    /// The ingredients by component, in the dish's order.
    public let ingredients: [(component: String, lines: [String])]

    public static func == (lhs: KitchenPlanSheet, rhs: KitchenPlanSheet) -> Bool {
        lhs.title == rhs.title && lhs.steps == rhs.steps && lhs.minutes == rhs.minutes
            && lhs.startText == rhs.startText && lhs.finishText == rhs.finishText
            && lhs.ingredients.map(\.component) == rhs.ingredients.map(\.component)
            && lhs.ingredients.map(\.lines) == rhs.ingredients.map(\.lines)
    }

    public init(dish: KitchenDish, schedule: KitchenSchedule, start: Date? = nil,
                locale: Locale = AppSettings.locale, timeZone: TimeZone = .current) {
        title = dish.name
        servings = dish.servings
        minutes = schedule.makespan
        var format = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        format.timeZone = timeZone
        func text(_ minute: Int) -> String {
            guard let start else { return "\(minute)′" }
            return start.addingTimeInterval(TimeInterval(minute * 60)).formatted(format)
        }
        startText = start.map { $0.formatted(format) }
        finishText = start.map { $0.addingTimeInterval(TimeInterval(schedule.makespan * 60)).formatted(format) }
        let ordered = schedule.placements.sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        steps = ordered.enumerated().map { index, placement in
            let task = placement.task
            return Step(number: index + 1, taskID: task.id, name: task.name, component: task.component,
                        start: placement.start, end: placement.end,
                        startText: text(placement.start), endText: text(placement.end),
                        handsMinutes: task.handsMinutes, unattendedMinutes: task.unattendedMinutes,
                        station: task.station, ovenTemperature: task.ovenTemperature,
                        ingredients: dish.ingredients(for: task).map { $0.line(locale: locale) })
        }
        ingredients = KitchenShoppingList.groups(of: dish).map { group in
            (component: group.component, lines: group.ingredients.map { $0.line(locale: locale) })
        }
    }

    /// The step numbers by task, for the timeline's bars.
    public var numbers: [String: Int] {
        Dictionary(uniqueKeysWithValues: steps.map { ($0.taskID, $0.number) })
    }
}
