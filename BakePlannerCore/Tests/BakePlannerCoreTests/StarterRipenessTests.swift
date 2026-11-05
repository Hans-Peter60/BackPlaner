//
//  StarterRipenessTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("When a starter is ripe, from its diary")
struct StarterRipenessTests {

    private typealias Observation = StarterRipeness.Observation

    @Test("One feeding at the reference temperature, read at warmer and colder")
    func singleFeeding() throws {
        let diary = [Observation(temperature: 22, peakMinutes: 300)]
        let same = try #require(StarterRipeness.estimate(from: diary, at: 22))
        #expect(same.minutes == 300)
        #expect(same.observations == 1)
        #expect(!same.fitted && same.q10 == StarterRipeness.defaultQ10)

        // Ten degrees warmer: 2.5 times as fast. Ten degrees colder: 2.5 times as slow.
        #expect(StarterRipeness.estimate(from: diary, at: 32)?.minutes == 120)
        #expect(StarterRipeness.estimate(from: diary, at: 12)?.minutes == 750)
    }

    @Test("Feedings at other temperatures are brought to the reference, the middle one counts")
    func medianOfNormalized() throws {
        // Three degrees of span: too little to fit the factor, so the default
        // applies. 228 min at 25 °C is 228 · 2.5^0.3 ≈ 300 min at 22 °C; the
        // bad day with 900 min is the odd one out and does not count.
        let diary = [Observation(temperature: 25, peakMinutes: 228),
                     Observation(temperature: 22, peakMinutes: 300),
                     Observation(temperature: 22, peakMinutes: 900)]
        let estimate = try #require(StarterRipeness.estimate(from: diary, at: 22))
        #expect(estimate.minutes == 300)
        #expect(estimate.observations == 3)
        #expect(!estimate.fitted)
    }

    @Test("Enough feedings over a temperature span fit the factor to this starter")
    func fitsTheFactor() throws {
        // This starter is slower to react to warmth: ~2.0 per 10 °C.
        let diary = [Observation(temperature: 28, peakMinutes: 200),
                     Observation(temperature: 22, peakMinutes: 300),
                     Observation(temperature: 16, peakMinutes: 460)]
        let estimate = try #require(StarterRipeness.estimate(from: diary, at: 22))
        #expect(estimate.fitted)
        #expect(abs(estimate.q10 - 2.0) < 0.1)
        #expect(abs(Double(estimate.minutes) - 300) <= 10)
    }

    @Test("Too few feedings, or all at the same temperature, keep the default factor")
    func noFitWithoutSpan() throws {
        let alike = [Observation(temperature: 22, peakMinutes: 300),
                     Observation(temperature: 23, peakMinutes: 290),
                     Observation(temperature: 22, peakMinutes: 310)]
        let estimate = try #require(StarterRipeness.estimate(from: alike, at: 22))
        #expect(!estimate.fitted)
        let two = [Observation(temperature: 16, peakMinutes: 500), Observation(temperature: 28, peakMinutes: 150)]
        #expect(StarterRipeness.estimate(from: two, at: 22)?.fitted == false)
    }

    @Test("A wild fit is held within the range of fermentation")
    func clampsTheFactor() throws {
        let wild = [Observation(temperature: 18, peakMinutes: 2000),
                     Observation(temperature: 22, peakMinutes: 300),
                     Observation(temperature: 26, peakMinutes: 40)]
        let estimate = try #require(StarterRipeness.estimate(from: wild, at: 22))
        #expect(estimate.q10 == StarterRipeness.q10Range.upperBound)
    }

    @Test("Only the recent feedings count, and none at all gives no estimate")
    func recentOnly() {
        let old = Array(repeating: Observation(temperature: 22, peakMinutes: 600), count: 10)
        let recent = Array(repeating: Observation(temperature: 22, peakMinutes: 300), count: 8)
        #expect(StarterRipeness.estimate(from: recent + old, at: 22)?.minutes == 300)
        #expect(StarterRipeness.estimate(from: [], at: 22) == nil)
        #expect(StarterRipeness.estimate(from: [Observation(temperature: 22, peakMinutes: 0)], at: 22) == nil)
    }

    @Test("The ready time follows from the feeding time")
    func readyDate() throws {
        let estimate = try #require(StarterRipeness.estimate(from: [Observation(temperature: 22, peakMinutes: 300)], at: 22))
        let fed = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(estimate.readyDate(fedAt: fed) == fed.addingTimeInterval(300 * 60))
    }
}
