//
//  ScheduledStepShiftTests.swift
//  BackPlanerTests
//
//  Which planned steps count as "the following ones" when a step is shifted
//  together with them, and where the plan puts its finish.
//

import CoreData
import Foundation
import Testing
@testable import BackPlaner

// On the main actor: the fetches go through the view context, which is a
// main-queue context.
@Suite("Shifting a planned step with its followers")
@MainActor
struct ScheduledStepShiftTests {

    private let planID = UUID()
    private let bakeDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func minute(_ offset: Int) -> Date {
        bakeDate.addingTimeInterval(TimeInterval(offset * 60))
    }

    @discardableResult
    private func step(_ number: Double, at date: Date, recipe: String = "Brot", plan: UUID?,
                      in context: NSManagedObjectContext) -> NextStep {
        let step = NextStep(context: context)
        step.id = UUID()
        step.recipeName = recipe
        step.instruction = "Schritt \(number)"
        step.step = number
        step.date = date
        step.planID = plan
        return step
    }

    @Test("The finish at the bake's own minute follows the bake; what lies before it does not")
    func sameMinuteFollowers() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        step(9, at: minute(-30), plan: planID, in: context)          // before the bake
        step(9.9, at: minute(0), plan: planID, in: context)          // same minute, lower number (oven step)
        step(10, at: minute(0), plan: planID, in: context)           // the bake itself
        step(10.1, at: minute(20), plan: planID, in: context)        // later
        step(99, at: minute(0), plan: planID, in: context)           // the finish, no bake duration recorded
        step(10, at: minute(0), recipe: "Kuchen", plan: planID, in: context)
        step(11, at: minute(0), plan: UUID(), in: context)           // another plan of the same recipe
        try context.save()

        let request = NextStep.fetchRequest()
        request.predicate = NotificationActions.followingStepsPredicate(
            recipeName: "Brot", after: bakeDate, step: 10, planID: planID)
        let found = try context.fetch(request).map(\.step).sorted()
        #expect(found == [10.1, 99])
    }

    @Test("Without a step number only later steps follow, as before")
    func dateOnlyFollowers() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        step(10, at: minute(0), plan: nil, in: context)
        step(99, at: minute(0), plan: nil, in: context)
        step(10.1, at: minute(20), plan: nil, in: context)
        step(11, at: minute(5), plan: planID, in: context)           // another plan
        // "planID == nil" is answered by the store, not by the pending inserts.
        try context.save()

        let request = NextStep.fetchRequest()
        request.predicate = NotificationActions.followingStepsPredicate(
            recipeName: "Brot", after: bakeDate, step: nil, planID: nil)
        let found = try context.fetch(request).map(\.step)
        #expect(found == [10.1])
    }

    @Test("A reminder at the same minute follows by its step text")
    func reminderOrder() {
        let current = bakeDate
        #expect(NotificationActions.reminderFollows(date: minute(20), stepText: "10.1", currentDate: current, currentStep: 10))
        #expect(NotificationActions.reminderFollows(date: minute(0), stepText: "99", currentDate: current, currentStep: 10))
        #expect(!NotificationActions.reminderFollows(date: minute(0), stepText: "9.9", currentDate: current, currentStep: 10))
        #expect(!NotificationActions.reminderFollows(date: minute(-30), stepText: "9", currentDate: current, currentStep: 10))
        // Without numbers the minute alone decides, as it used to.
        #expect(!NotificationActions.reminderFollows(date: minute(0), stepText: nil, currentDate: current, currentStep: 10))
        #expect(!NotificationActions.reminderFollows(date: minute(0), stepText: "99", currentDate: current, currentStep: nil))
    }

    @Test("The finish never comes before the last step has ended")
    func finishAfterTheLastStep() {
        let steps = [
            PlanStep(instruction: "Teig kneten", step: 1, startTime: 0, duration: 10),
            PlanStep(instruction: "Bei 250 °C backen", step: 2, startTime: 10, duration: 50)
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 18))!

        // A stored total that fell behind the steps.
        let stale = BakePlan(recipeName: "Brot", steps: steps, prepTime: 10, anchor: .finishesBy,
                             date: date, languageCode: "de", preheatTime: 15, calendar: calendar)
        #expect(stale.totalMinutes == 60)
        #expect(stale.endStep.startTime == 60)
        #expect(stale.date(of: stale.endStep) == date)

        // A total beyond the steps (cooling counted in) is kept.
        let generous = BakePlan(recipeName: "Brot", steps: steps, prepTime: 90, anchor: .startsAt,
                                date: date, languageCode: "de", preheatTime: 15, calendar: calendar)
        #expect(generous.endStep.startTime == 90)
    }
}
