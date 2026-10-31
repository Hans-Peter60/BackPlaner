//
//  ScheduledStepShiftTests.swift
//  BakePlannerCoreTests
//
//  Moving a planned step with or without its followers: the cases the iOS
//  app's tests check against its Core Data fetch, here against the rule in
//  the package.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Shifting a planned step with its followers (package rule)")
struct ScheduledStepShiftRuleTests {

    private let planID = UUID()
    private let bakeDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func minute(_ offset: Int) -> Date {
        bakeDate.addingTimeInterval(TimeInterval(offset * 60))
    }

    private func step(_ key: String, _ number: Double, at offset: Int, recipe: String = "Brot",
                      plan: UUID?) -> StoredScheduledStep {
        StoredScheduledStep(key: key, data: ScheduledStepData(
            id: UUID(), planID: plan, recipeName: recipe, instruction: "Schritt \(number)", step: number,
            startTime: 0, duration: 0, date: minute(offset), isAutomaticRecurrence: false, servingScale: 1))
    }

    @Test("The finish at the bake's own minute follows the bake; what lies before it does not")
    func sameMinuteFollowers() throws {
        let steps = [
            step("before", 9, at: -30, plan: planID),
            step("oven", 9.9, at: 0, plan: planID),        // same minute, lower number
            step("bake", 10, at: 0, plan: planID),
            step("later", 10.1, at: 20, plan: planID),
            step("finish", 99, at: 0, plan: planID),       // no bake duration recorded
            step("cake", 10, at: 0, recipe: "Kuchen", plan: planID),
            step("otherPlan", 11, at: 0, plan: UUID()),
        ]
        let dates = try ScheduledStepShift.newDates(shifting: "bake", byMinutes: 15, includeFollowing: true,
                                                    in: steps, now: minute(-100))
        #expect(Set(dates.keys) == ["bake", "later", "finish"])
        #expect(dates["bake"] == minute(15) && dates["later"] == minute(35) && dates["finish"] == minute(15))
    }

    @Test("Steps stored before plans had an id belong together by recipe")
    func withoutPlanID() throws {
        let steps = [
            step("bake", 10, at: 0, plan: nil),
            step("finish", 99, at: 0, plan: nil),
            step("later", 10.1, at: 20, plan: nil),
            step("otherPlan", 11, at: 5, plan: planID),
        ]
        let dates = try ScheduledStepShift.newDates(shifting: "bake", byMinutes: 10, includeFollowing: true,
                                                    in: steps, now: minute(-100))
        #expect(Set(dates.keys) == ["bake", "finish", "later"])
    }

    /// A rest with two folds inside it, then the bake. On the iPhone the rest
    /// once moved twice as far — the followers were looked up on its already
    /// changed date. Here they are found on the dates before the move.
    @Test("Shifting a step with its followers keeps their spacing, later and earlier")
    func followersKeepTheirSpacing() throws {
        var steps = [
            step("rest", 3, at: 0, plan: planID),
            step("firstFold", 3.1, at: 30, plan: planID),
            step("secondFold", 3.2, at: 60, plan: planID),
            step("bake", 4, at: 120, plan: planID),
            step("earlier", 2, at: -60, plan: planID),
        ]
        func apply(_ dates: [String: Date]) {
            for index in steps.indices {
                if let date = dates[steps[index].key] { steps[index].data.date = date }
            }
        }
        func date(_ key: String) -> Date? { steps.first { $0.key == key }?.data.date }

        apply(try ScheduledStepShift.newDates(shifting: "rest", byMinutes: 30, includeFollowing: true,
                                              in: steps, now: minute(-100)))
        #expect(date("rest") == minute(30) && date("firstFold") == minute(60) && date("secondFold") == minute(90))
        #expect(date("bake") == minute(150) && date("earlier") == minute(-60))

        apply(try ScheduledStepShift.newDates(shifting: "rest", byMinutes: -15, includeFollowing: true,
                                              in: steps, now: minute(-100)))
        #expect(date("rest") == minute(15) && date("firstFold") == minute(45) && date("bake") == minute(135))

        apply(try ScheduledStepShift.newDates(shifting: "firstFold", byMinutes: 5, includeFollowing: false,
                                              in: steps, now: minute(-100)))
        #expect(date("firstFold") == minute(50) && date("secondFold") == minute(75))
    }

    @Test("A step cannot be moved to now or before, nor one that is gone")
    func refused() {
        let steps = [step("rest", 3, at: 0, plan: planID)]
        #expect(throws: ScheduledStepShift.Failure.dateInPast) {
            try ScheduledStepShift.newDates(shifting: "rest", byMinutes: -30, includeFollowing: false,
                                            in: steps, now: minute(-30))
        }
        #expect(throws: ScheduledStepShift.Failure.unknownStep) {
            try ScheduledStepShift.newDates(shifting: "none", byMinutes: 5, includeFollowing: false,
                                            in: steps, now: minute(-30))
        }
    }
}
