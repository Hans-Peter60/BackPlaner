//
//  PlanOverlapTests.swift
//  BakePlannerCoreTests
//
//  Bakes of the same recipe planned twice: one oven phase per plan, and the
//  check when a plan is kept in addition to an earlier one.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Plans of the same recipe")
struct PlanOverlapTests {

    /// A fixed noon so the day window never adds findings of its own.
    private let noon = Calendar.current.date(
        from: DateComponents(year: 2026, month: 10, day: 3, hour: 12)
    )!

    private func minute(_ offset: Int) -> Date {
        noon.addingTimeInterval(TimeInterval(offset * 60))
    }

    /// Knead, bake, finish — oven phase from the bake (start + 60) to the
    /// finish (start + 120), as one plan.
    private func bake(_ recipe: String, startingAt start: Int, plan: UUID? = UUID()) -> [ScheduledStepData] {
        [
            (1.0, "Teig kneten", start),
            (2.0, "Im Ofen backen", start + 60),
            (99.0, "Backvorgang ist beendet", start + 120),
        ].map { step, instruction, offset in
            ScheduledStepData(id: UUID(), planID: plan, recipeName: recipe, instruction: instruction,
                              step: step, startTime: 0, duration: 0, date: minute(offset),
                              isAutomaticRecurrence: false, servingScale: 1)
        }
    }

    private func window(_ recipe: String, from start: Int, to end: Int) -> BakeWindow {
        BakeWindow(recipeName: recipe, start: minute(start), end: minute(end))
    }

    private func errors(_ issues: [BakePlanIssue]) -> Int {
        issues.filter { $0.severity == .error }.count
    }

    private func hints(_ issues: [BakePlanIssue]) -> Int {
        issues.filter { $0.severity == .hint }.count
    }

    @Test("Each plan of a recipe has its own oven phase")
    func windowPerPlan() {
        let store = InMemoryScheduledStepStore(bake("Brot", startingAt: 0) + bake("Brot", startingAt: 240))
        let windows = BakePlanValidator.scheduledBakeWindows(excluding: "Kuchen", from: store, now: minute(-60))
        #expect(windows.map(\.start) == [minute(60), minute(300)])
        #expect(windows.map(\.end) == [minute(120), minute(360)])
    }

    @Test("Steps without a plan ID still belong together by recipe")
    func legacyStepsByRecipe() {
        let store = InMemoryScheduledStepStore(bake("Brot", startingAt: 0, plan: nil))
        let windows = BakePlanValidator.scheduledBakeWindows(from: store, now: minute(-60))
        #expect(windows.count == 1)
        #expect(windows.first?.start == minute(60))
        #expect(windows.first?.end == minute(120))
    }

    @Test("Another recipe's second plan counts when a bake is checked")
    func otherRecipesSecondPlanCounts() {
        let store = InMemoryScheduledStepStore(bake("Brot", startingAt: 0) + bake("Brot", startingAt: 240))
        let existing = BakePlanValidator.scheduledBakeWindows(excluding: "Kuchen", from: store, now: minute(-60))
        // The cake bakes during the second loaf.
        let found = BakePlanValidator.issues(for: [], bakeWindow: window("Kuchen", from: 310, to: 340),
                                             existingWindows: existing, ovenCount: 1, bakePause: 0)
        #expect(errors(found) == 1)
    }

    @Test("Planned in addition, a second loaf in the same oven time is an error with one oven")
    func additionalPlanOneOven() {
        let store = InMemoryScheduledStepStore(bake("Brot", startingAt: 0))
        let existing = BakePlanValidator.scheduledBakeWindows(from: store, now: minute(-60))
        let found = BakePlanValidator.issues(for: [], bakeWindow: window("Brot", from: 90, to: 150),
                                             existingWindows: existing, ovenCount: 1, bakePause: 0)
        #expect(errors(found) == 1)
    }

    @Test("With two ovens the second loaf is a hint")
    func additionalPlanTwoOvens() {
        let store = InMemoryScheduledStepStore(bake("Brot", startingAt: 0))
        let existing = BakePlanValidator.scheduledBakeWindows(from: store, now: minute(-60))
        let found = BakePlanValidator.issues(for: [], bakeWindow: window("Brot", from: 90, to: 150),
                                             existingWindows: existing, ovenCount: 2, bakePause: 0)
        #expect(errors(found) == 0)
        #expect(hints(found) == 1)
    }

    @Test("Without an overlap planning in addition finds nothing")
    func additionalPlanApart() {
        let store = InMemoryScheduledStepStore(bake("Brot", startingAt: 0))
        let existing = BakePlanValidator.scheduledBakeWindows(from: store, now: minute(-60))
        let found = BakePlanValidator.issues(for: [], bakeWindow: window("Brot", from: 300, to: 360),
                                             existingWindows: existing, ovenCount: 1, bakePause: 10)
        #expect(found.isEmpty)
    }

    @Test("Replacing leaves the recipe's earlier plan out of the check")
    func replacingIgnoresOwnPlan() {
        let store = InMemoryScheduledStepStore(bake("Brot", startingAt: 0))
        let existing = BakePlanValidator.scheduledBakeWindows(excluding: "Brot", from: store, now: minute(-60))
        #expect(existing.isEmpty)
    }
}
