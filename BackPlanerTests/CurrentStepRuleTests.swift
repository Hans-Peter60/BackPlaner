//
//  CurrentStepRuleTests.swift
//  BackPlanerTests
//
//  Which planned step matters right now, and when an automatically queued
//  step becomes visible — on plain dates, without Core Data.
//

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
