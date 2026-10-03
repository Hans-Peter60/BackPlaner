//
//  BakePlanValidatorTests.swift
//  BackPlanerTests
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("Bake plan check against the number of ovens")
struct BakePlanValidatorTests {

    /// A fixed noon so the day window never adds hints of its own.
    private let noon = Calendar.current.date(
        from: DateComponents(year: 2026, month: 10, day: 3, hour: 12)
    )!

    /// A bake running from `start` to `end`, both in minutes after noon.
    private func bake(_ name: String, from start: Int, to end: Int) -> BakeWindow {
        BakeWindow(
            recipeName: name,
            start: noon.addingTimeInterval(TimeInterval(start * 60)),
            end: noon.addingTimeInterval(TimeInterval(end * 60))
        )
    }

    private func issues(
        for window: BakeWindow,
        existing: [BakeWindow],
        ovens: Int,
        pause: Int = 10
    ) -> [BakePlanIssue] {
        BakePlanValidator.issues(
            for: [],
            bakeWindow: window,
            existingWindows: existing,
            ovenCount: ovens,
            bakePause: pause
        )
    }

    private func errors(in issues: [BakePlanIssue]) -> Int {
        issues.filter { $0.severity == .error }.count
    }

    private func hints(in issues: [BakePlanIssue]) -> Int {
        issues.filter { $0.severity == .hint }.count
    }

    // MARK: - Overlaps

    @Test("With one oven any overlap is an error")
    func singleOvenOverlapIsError() {
        let found = issues(
            for: bake("Brot", from: 0, to: 60),
            existing: [bake("Brötchen", from: 30, to: 90)],
            ovens: 1
        )
        #expect(errors(in: found) == 1)
        #expect(hints(in: found) == 0)
    }

    @Test("With two ovens one overlapping bake is only a hint")
    func secondOvenTakesTheOverlap() {
        let found = issues(
            for: bake("Brot", from: 0, to: 60),
            existing: [bake("Brötchen", from: 30, to: 90)],
            ovens: 2
        )
        #expect(errors(in: found) == 0)
        #expect(hints(in: found) == 1)
        #expect(found.first?.message.contains("Brötchen") == true)
    }

    @Test("With two ovens a third simultaneous bake is an error")
    func thirdBakeExceedsTwoOvens() {
        let found = issues(
            for: bake("Brot", from: 0, to: 60),
            existing: [
                bake("Brötchen", from: 30, to: 90),
                bake("Zopf", from: 20, to: 50)
            ],
            ovens: 2
        )
        #expect(errors(in: found) == 1)
        #expect(found.first?.message.contains("Brötchen") == true)
        #expect(found.first?.message.contains("Zopf") == true)
    }

    @Test("Two overlaps that never run at the same time share the second oven")
    func overlapsInSequenceFitIntoOneSpareOven() {
        let found = issues(
            for: bake("Brot", from: 0, to: 120),
            existing: [
                bake("Brötchen", from: 10, to: 40),
                bake("Zopf", from: 60, to: 100)
            ],
            ovens: 2
        )
        #expect(errors(in: found) == 0)
        #expect(hints(in: found) == 2)
    }

    @Test("A bake that stops the moment the next one starts does not overlap")
    func touchingWindowsDoNotOverlap() {
        #expect(BakePlanValidator.peakConcurrency(
            of: [bake("Brötchen", from: 60, to: 90)],
            within: bake("Brot", from: 0, to: 60),
            padding: 0
        ) == 0)
    }

    // MARK: - Pause

    @Test("With one oven a gap shorter than the pause is a hint")
    func singleOvenShortGapIsHint() {
        let found = issues(
            for: bake("Brot", from: 65, to: 120),
            existing: [bake("Brötchen", from: 0, to: 60)],
            ovens: 1
        )
        #expect(errors(in: found) == 0)
        #expect(hints(in: found) == 1)
    }

    @Test("With two ovens a short gap needs no hint, the other oven is cold")
    func spareOvenNeedsNoPause() {
        let found = issues(
            for: bake("Brot", from: 65, to: 120),
            existing: [bake("Brötchen", from: 0, to: 60)],
            ovens: 2
        )
        #expect(found.isEmpty)
    }

    @Test("With two ovens the pause matters once the other oven is in use")
    func pauseAppliesWhenSpareOvenIsBusy() {
        let found = issues(
            for: bake("Brot", from: 65, to: 120),
            existing: [
                bake("Brötchen", from: 0, to: 60),
                bake("Zopf", from: 50, to: 100)
            ],
            ovens: 2
        )
        #expect(errors(in: found) == 0)
        // One hint for the overlap with Zopf, one for the short gap after Brötchen.
        #expect(hints(in: found) == 2)
    }

    @Test("A pause of zero switches the gap check off")
    func zeroPauseSkipsGapCheck() {
        let found = issues(
            for: bake("Brot", from: 60, to: 120),
            existing: [bake("Brötchen", from: 0, to: 60)],
            ovens: 1,
            pause: 0
        )
        #expect(found.isEmpty)
    }

    @Test("A stored oven count below one still behaves like a single oven")
    func ovenCountIsAtLeastOne() {
        let found = issues(
            for: bake("Brot", from: 0, to: 60),
            existing: [bake("Brötchen", from: 30, to: 90)],
            ovens: 0
        )
        #expect(errors(in: found) == 1)
    }
}
