//
//  StarterDiagram.swift
//  BakePlannerCore
//
//  What the starter's diagram shows: the ripening curve over temperature
//  from the diary's model, the feedings over time brought to one
//  temperature, the feeding that is ripening right now, the rhythm, and
//  the diary as CSV. The drawing is the apps' job.
//

import Foundation

public enum StarterDiagram {

    /// One feeding of the diary as the diagram reads it.
    public struct Feeding: Equatable {
        public let date: Date
        public let facts: StarterFeedingFacts

        public init(date: Date, facts: StarterFeedingFacts) {
            self.date = date
            self.facts = facts
        }
    }

    // MARK: Ripening curve

    /// The temperatures the curve is drawn over: the span the room
    /// temperature stepper offers.
    public static let curveTemperatures: [Double] = Array(stride(from: 10.0, through: 35.0, by: 1.0))

    public struct CurvePoint: Identifiable, Equatable {
        public let temperature: Double
        public let minutes: Int
        public var id: Double { temperature }
    }

    /// The model's ripening time at every curve temperature.
    public static func curve(for estimate: StarterRipeness.Estimate) -> [CurvePoint] {
        curveTemperatures.map { CurvePoint(temperature: $0, minutes: estimate.minutes(at: $0)) }
    }

    /// The feedings that measured both, as points beside the curve.
    public static func observations(_ feedings: [Feeding]) -> [StarterRipeness.Observation] {
        StarterFeedingFacts.ripenessObservations(feedings.sorted { $0.date > $1.date }.map(\.facts))
    }

    // MARK: Trend

    /// One feeding with a measured peak, in time: as measured and as it
    /// would have run at the reference temperature, so a starter getting
    /// livelier or sluggish shows regardless of the kitchen's weather.
    public struct TrendPoint: Identifiable, Equatable {
        public let date: Date
        public let peakMinutes: Int
        public let atReferenceMinutes: Int
        public let temperature: Double?
        public let floatTestPassed: Bool?
        public var id: Date { date }
    }

    /// Chronological. A feeding without a temperature counts as fed at the
    /// reference temperature.
    public static func trend(_ feedings: [Feeding], q10: Double) -> [TrendPoint] {
        feedings
            .filter { ($0.facts.peakMinutes ?? 0) > 0 }
            .sorted { $0.date < $1.date }
            .map { feeding in
                let minutes = feeding.facts.peakMinutes ?? 0
                let temperature = feeding.facts.roomTemperature
                let factor = pow(q10, ((temperature ?? StarterRipeness.referenceTemperature) - StarterRipeness.referenceTemperature) / 10)
                return TrendPoint(date: feeding.date, peakMinutes: minutes,
                                  atReferenceMinutes: Plausible.roundedInt(Double(minutes) * factor),
                                  temperature: temperature, floatTestPassed: feeding.facts.floatTestPassed)
            }
    }

    // MARK: The feeding under way

    /// How long a feeding counts as "under way" without a result.
    public static let underWayHours = 48.0

    public struct Progress: Equatable {
        public let fedAt: Date
        public let readyAt: Date

        public init(fedAt: Date, readyAt: Date) {
            self.fedAt = fedAt
            self.readyAt = readyAt
        }

        /// 0 at the feeding, 1 at the predicted peak, beyond it afterwards.
        public func fraction(at now: Date) -> Double {
            let total = readyAt.timeIntervalSince(fedAt)
            guard total > 0 else { return 1 }
            return max(0, now.timeIntervalSince(fedAt) / total)
        }

        public func isRipe(at now: Date) -> Bool { now >= readyAt }
    }

    /// The newest feeding that has begun, has no peak noted yet and is not
    /// older than two days.
    public static func underWay(_ feedings: [Feeding], now: Date) -> Feeding? {
        feedings
            .filter { $0.date <= now && ($0.facts.peakMinutes ?? 0) == 0
                      && now.timeIntervalSince($0.date) <= underWayHours * 3600 }
            .max { $0.date < $1.date }
    }

    /// The feeding under way with the moment the model expects its peak.
    public static func progress(_ feedings: [Feeding], estimate: StarterRipeness.Estimate, now: Date) -> Progress? {
        guard let feeding = underWay(feedings, now: now) else { return nil }
        return Progress(fedAt: feeding.date, readyAt: estimate.readyDate(fedAt: feeding.date))
    }

    // MARK: Rhythm

    public struct Rhythm: Equatable {
        /// Feedings in the last 30 days.
        public let lastMonthCount: Int
        /// Mean days between consecutive feedings of the last eight; nil
        /// with fewer than two.
        public let averageIntervalDays: Double?
        /// Whole days since the last feeding that has begun; nil without one.
        public let daysSinceLast: Int?
    }

    public static func rhythm(_ feedings: [Feeding], now: Date, calendar: Calendar = .current) -> Rhythm {
        let begun = feedings.filter { $0.date <= now }.sorted { $0.date > $1.date }
        let monthAgo = now.addingTimeInterval(-30 * 24 * 3600)
        let recent = Array(begun.prefix(StarterRipeness.recentCount))
        var interval: Double?
        if recent.count >= 2 {
            let span = recent[0].date.timeIntervalSince(recent[recent.count - 1].date)
            interval = span / Double(recent.count - 1) / (24 * 3600)
        }
        let daysSinceLast = begun.first.map {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.date), to: calendar.startOfDay(for: now)).day ?? 0
        }
        return Rhythm(lastMonthCount: begun.filter { $0.date >= monthAgo }.count,
                      averageIntervalDays: interval, daysSinceLast: daysSinceLast)
    }

    // MARK: CSV

    /// The diary as text for a spreadsheet: one line per feeding, oldest
    /// first, semicolons between the columns (what a German Excel opens
    /// as a table), ISO dates, a decimal point.
    public static func csv(_ feedings: [Feeding]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        formatter.timeZone = .current
        var lines = ["date;peak_minutes;room_temperature;float_test;note"]
        for feeding in feedings.sorted(by: { $0.date < $1.date }) {
            let facts = feeding.facts
            let temperature = facts.roomTemperature.map { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
            let float = facts.floatTestPassed.map { $0 ? "yes" : "no" } ?? ""
            lines.append([formatter.string(from: feeding.date),
                          facts.peakMinutes.map(String.init) ?? "",
                          temperature, float, csvField(facts.note)].joined(separator: ";"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ text: String) -> String {
        guard text.contains(where: { $0 == ";" || $0 == "\"" || $0.isNewline }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

extension StarterRipeness.Estimate {
    /// The model's ripening time at another temperature, to five minutes.
    public func minutes(at other: Double) -> Int {
        let value = Double(minutes) * pow(q10, (temperature - other) / 10)
        return max(5, Int((value / 5).rounded()) * 5)
    }
}
