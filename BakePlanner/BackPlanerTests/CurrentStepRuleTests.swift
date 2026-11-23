//
//  CurrentStepRuleTests.swift
//  BackPlanerTests
//
//  Which planned step matters right now, and when an automatically queued
//  step becomes visible — on plain dates, without Core Data.
//

import BakePlannerCore
import Foundation
import Testing
@testable import BackPlaner

@Suite("Which planned step matters now")
struct CurrentStepRuleTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func minutes(_ offset: Int) -> Date {
        now.addingTimeInterval(TimeInterval(offset * 60))
    }

    private func current(_ dates: [Date]) -> (step: Date, isDue: Bool)? {
        CurrentStepRule.currentStep(in: dates, at: now, date: { $0 })
    }

    @Test("A step due within the last hour comes before the one ahead")
    func dueStepComesFirst() throws {
        let found = try #require(current([minutes(-20), minutes(40)]))
        #expect(found.step == minutes(-20))
        #expect(found.isDue)
    }

    @Test("A step due exactly now counts as due")
    func stepDueNow() throws {
        let found = try #require(current([minutes(0), minutes(40)]))
        #expect(found.step == minutes(0))
        #expect(found.isDue)
    }

    @Test("After the grace period the due step is let go of")
    func oldDueStepIsLetGo() throws {
        let found = try #require(current([minutes(-60), minutes(40)]))
        #expect(found.step == minutes(40))
        #expect(!found.isDue)
    }

    @Test("A newer due step supersedes an older one")
    func newerDueStepWins() throws {
        let found = try #require(current([minutes(-50), minutes(-10), minutes(40)]))
        #expect(found.step == minutes(-10))
        #expect(found.isDue)
    }

    @Test("Nothing without steps, or with only steps long past")
    func nothingToShow() {
        #expect(current([]) == nil)
        #expect(current([minutes(-180), minutes(-90)]) == nil)
    }

    @Test("The rule and the widget's grace period are the same hour")
    func gracePeriod() {
        #expect(CurrentStepRule.dueGracePeriod == 60 * 60)
        #expect(PlanSnapshot.dueGracePeriod == CurrentStepRule.dueGracePeriod)
    }

    @Test("A step planned by hand is always visible, an automatic one from two days before")
    func visibility() {
        let lead = Int(RecurringBakePlanner.visibilityLeadTime / 60)

        #expect(RecurringBakePlanner.isVisible(date: minutes(10 * lead), isAutomaticRecurrence: false, at: now))
        #expect(RecurringBakePlanner.isVisible(date: minutes(lead), isAutomaticRecurrence: true, at: now))
        #expect(!RecurringBakePlanner.isVisible(date: minutes(lead + 1), isAutomaticRecurrence: true, at: now))

        let step = ScheduledStepData(id: UUID(), planID: nil, recipeName: "Anstellgut", instruction: "Füttern",
                                     step: 1, startTime: 0, duration: 0, date: minutes(lead + 1),
                                     isAutomaticRecurrence: true, servingScale: 1)
        #expect(!step.isVisible(at: now))
        #expect(step.isVisible(at: minutes(1)))
    }
}

@Suite("What the widget's buttons hand to the app")
struct WidgetActionTests {

    @Test("The shift link names the step, other links name none")
    func shiftLink() {
        let id = UUID().uuidString
        let url = PlanSnapshot.shiftURL(for: id)
        #expect(url.scheme == "bakeplanner")
        #expect(url.host() == "scheduled-steps")
        #expect(PlanSnapshot.shiftStepID(from: url) == id)

        #expect(PlanSnapshot.shiftStepID(from: PlanSnapshot.scheduledStepsURL) == nil)
        #expect(PlanSnapshot.shiftStepID(from: URL(string: "bakeplanner://scheduled-steps?shift=")!) == nil)
        #expect(PlanSnapshot.shiftStepID(from: URL(string: "https://example.com/?shift=\(id)")!) == nil)
    }

    @Test("A step the widget marks done leaves the snapshot, the others stay in order")
    func removingStep() {
        let now = Date()
        let steps = (1...3).map {
            PlanSnapshot.Step(id: "step-\($0)", recipeName: "Brot", instruction: "Schritt \($0)",
                              date: now.addingTimeInterval(Double($0) * 600), duration: 10)
        }
        let snapshot = PlanSnapshot(steps: steps, generatedAt: now.addingTimeInterval(-60))

        let remaining = snapshot.removingStep(id: "step-2")
        #expect(remaining.steps.map(\.id) == ["step-1", "step-3"])
        #expect(remaining.generatedAt >= now)
        #expect(snapshot.removingStep(id: "unknown").steps == steps)
    }

    @Test("A snapshot carries a step's ingredients to the Watch, and reads an older file without them")
    func ingredientLines() throws {
        let step = PlanSnapshot.Step(id: "a", recipeName: "Brot", instruction: "Mischen",
                                     date: Date(timeIntervalSince1970: 1_700_000_000), duration: 10,
                                     componentName: "Hauptteig", ingredientLines: ["• 500 g Mehl", "• 10 g Salz"])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let copy = try decoder.decode(PlanSnapshot.self,
                                      from: encoder.encode(PlanSnapshot(steps: [step], generatedAt: step.date)))
        #expect(copy.steps == [step])

        let old = """
        {"steps":[{"id":"b","recipeName":"Brot","instruction":"Backen","date":"2026-11-04T06:00:00Z","duration":45}],\
        "generatedAt":"2026-11-04T05:00:00Z"}
        """
        let decoded = try decoder.decode(PlanSnapshot.self, from: Data(old.utf8))
        #expect(decoded.steps.first?.duration == 45)
        #expect(decoded.steps.first?.ingredientLines == nil)
        #expect(decoded.steps.first?.componentName == nil)
    }
}
