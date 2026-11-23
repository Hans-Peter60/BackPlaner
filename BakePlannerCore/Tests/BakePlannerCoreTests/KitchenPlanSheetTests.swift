import Foundation
import Testing
@testable import BakePlannerCore

@Suite("CookPlanner: the printed plan")
struct KitchenPlanSheetTests {

    private let german = Locale(identifier: "de_DE")
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func schedule(_ dish: KitchenDish) throws -> KitchenSchedule {
        try KitchenScheduler.schedule(dish.tasks, kitchen: Kitchen(), budget: 45)
    }

    @Test("Steps in the order they begin, numbered, with full text and their ingredients")
    func steps() throws {
        let dish = KitchenSampleDishes.perlhuhnbrust
        let sheet = KitchenPlanSheet(dish: dish, schedule: try schedule(dish), locale: german, timeZone: berlin)
        #expect(sheet.steps.count == dish.tasks.count)
        #expect(sheet.steps.map(\.number) == Array(1...dish.tasks.count))
        #expect(zip(sheet.steps, sheet.steps.dropFirst()).allSatisfy { $0.start <= $1.start })
        #expect(sheet.steps.first?.startText == "0′")
        let wirsing = try #require(sheet.steps.first { $0.taskID == "w1" })
        #expect(wirsing.name == dish.tasks.first { $0.id == "w1" }?.name)
        #expect(!wirsing.ingredients.isEmpty)
        #expect(sheet.startText == nil && sheet.finishText == nil)
        #expect(sheet.ingredients.map(\.component).first == dish.components.first)
        #expect(sheet.numbers[sheet.steps[2].taskID] == 3)
    }

    @Test("With a start time every step has its clock time, and the finish follows")
    func clock() throws {
        let dish = KitchenSampleDishes.perlhuhnbrust
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 18, minute: 0))!
        let plan = try schedule(dish)
        let sheet = KitchenPlanSheet(dish: dish, schedule: plan, start: start, locale: german, timeZone: berlin)
        #expect(sheet.startText == "18:00")
        #expect(sheet.steps.first?.startText == "18:00")
        let finish = calendar.date(byAdding: .minute, value: plan.makespan, to: start)!
        #expect(sheet.finishText == finish.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: german, timeZone: berlin)))
    }
}
