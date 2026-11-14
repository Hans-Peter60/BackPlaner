//
//  StarterDiagramTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("The starter's diagram")
struct StarterDiagramTests {

    private let calendar = Calendar(identifier: .gregorian)
    private func day(_ day: Int, hour: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }
    private func feeding(_ day: Int, hour: Int = 8, peak: Int? = nil, temperature: Double? = nil,
                         float: Bool? = nil, note: String = "") -> StarterDiagram.Feeding {
        StarterDiagram.Feeding(date: self.day(day, hour: hour),
                               facts: StarterFeedingFacts(peakMinutes: peak, floatTestPassed: float,
                                                          note: note, roomTemperature: temperature))
    }

    @Test("The curve follows the model: warmer is faster, the estimate's own point is on it")
    func curve() throws {
        let estimate = try #require(StarterRipeness.estimate(
            from: [.init(temperature: 22, peakMinutes: 480)], at: 22))
        let curve = StarterDiagram.curve(for: estimate)
        #expect(curve.count == StarterDiagram.curveTemperatures.count)
        #expect(curve.first { $0.temperature == 22 }?.minutes == 480)
        #expect(curve.first { $0.temperature == 32 }?.minutes == Int((480 / 2.5 / 5).rounded()) * 5)
        #expect(zip(curve, curve.dropFirst()).allSatisfy { $0.minutes >= $1.minutes })
        #expect(estimate.minutes(at: 12) == Int((480 * 2.5 / 5).rounded()) * 5)
    }

    @Test("The trend keeps feedings with a peak, oldest first, brought to 22 °C")
    func trend() {
        let feedings = [feeding(10, peak: 600, temperature: 18), feeding(5, peak: 480, temperature: 22),
                        feeding(12), feeding(14, peak: 300, temperature: 26, float: false)]
        let trend = StarterDiagram.trend(feedings, q10: 2.0)
        #expect(trend.map(\.date) == [day(5), day(10), day(14)])
        #expect(trend[1].atReferenceMinutes == Int((600 * pow(2.0, -0.4)).rounded()))
        #expect(trend[0].atReferenceMinutes == 480)
        #expect(trend[2].floatTestPassed == false)
    }

    @Test("The feeding under way is the newest without a result, not older than two days")
    func progress() throws {
        let estimate = try #require(StarterRipeness.estimate(from: [.init(temperature: 22, peakMinutes: 480)], at: 22))
        let now = day(14, hour: 12)
        let feedings = [feeding(14, hour: 8), feeding(13, hour: 8), feeding(10, peak: 480, temperature: 22)]
        let progress = try #require(StarterDiagram.progress(feedings, estimate: estimate, now: now))
        #expect(progress.fedAt == day(14))
        #expect(progress.readyAt == day(14, hour: 16))
        #expect(abs(progress.fraction(at: now) - 0.5) < 0.001)
        #expect(!progress.isRipe(at: now) && progress.isRipe(at: day(14, hour: 17)))

        #expect(StarterDiagram.progress([feeding(10)], estimate: estimate, now: now) == nil)
        #expect(StarterDiagram.progress([feeding(15)], estimate: estimate, now: now) == nil)
        #expect(StarterDiagram.progress([feeding(14, peak: 300)], estimate: estimate, now: now) == nil)
    }

    @Test("The rhythm counts the month, the mean gap and the days since the last feeding")
    func rhythm() {
        let now = day(20, hour: 12)
        let rhythm = StarterDiagram.rhythm([feeding(18), feeding(14), feeding(10), feeding(25), feeding(1)],
                                           now: now, calendar: calendar)
        #expect(rhythm.lastMonthCount == 4)
        #expect(rhythm.daysSinceLast == 2)
        let interval = rhythm.averageIntervalDays ?? 0
        #expect(abs(interval - 17.0 / 3.0) < 0.01)
        #expect(StarterDiagram.rhythm([], now: now, calendar: calendar) == .init(lastMonthCount: 0, averageIntervalDays: nil, daysSinceLast: nil))
    }

    @Test("The CSV has a header, oldest first, quoted notes and a decimal point")
    func csv() {
        let text = StarterDiagram.csv([feeding(14, peak: 300, temperature: 26.5, float: true, note: "riecht gut; mild"),
                                       feeding(10, peak: 480)])
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines[0] == "date;peak_minutes;room_temperature;float_test;note")
        #expect(lines[1].hasPrefix("2026-11-10T08:00:00") && lines[1].hasSuffix(";480;;;"))
        #expect(lines[2].hasSuffix(";300;26.5;yes;\"riecht gut; mild\""))
    }
}
