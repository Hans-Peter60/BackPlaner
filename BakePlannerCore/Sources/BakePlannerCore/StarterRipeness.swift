//
//  StarterRipeness.swift
//  BakePlannerCore
//
//  When a starter will be ripe today, judged from how it behaved before.
//  The feeding diary knows, per feeding, how long the starter took to peak
//  and at what room temperature. Fermentation runs faster when it is warm:
//  roughly two to three times as fast for every 10 °C, the Q10 of baker's
//  yeast and lactic acid bacteria. With that rule each past feeding is
//  brought to a reference temperature, the middle value taken, and the
//  time at today's temperature read back from it. With enough feedings at
//  different temperatures the rule itself is fitted to this starter.
//

import Foundation

public enum StarterRipeness {

    /// The temperature the past feedings are compared at.
    public static let referenceTemperature = 22.0
    /// How many times faster the starter ripens for 10 °C more, until the
    /// diary says otherwise.
    public static let defaultQ10 = 2.5
    /// What the fitted factor may be: slower than this is no fermentation,
    /// faster is a measuring error.
    public static let q10Range = 1.5...4.0
    /// Past feedings used; the older ones describe a starter that has since
    /// changed.
    public static let recentCount = 8
    /// Fitting the factor needs this many feedings over this temperature span.
    public static let fitMinimumCount = 3
    public static let fitMinimumSpan = 4.0

    /// One past feeding that measured both.
    public struct Observation: Equatable {
        public let temperature: Double
        public let peakMinutes: Int

        public init(temperature: Double, peakMinutes: Int) {
            self.temperature = temperature
            self.peakMinutes = peakMinutes
        }
    }

    public struct Estimate: Equatable {
        /// Minutes from feeding to peak at `temperature`, to five minutes.
        public let minutes: Int
        public let temperature: Double
        /// How many feedings the estimate rests on.
        public let observations: Int
        /// The factor per 10 °C used; `fitted` when it came from the diary
        /// rather than the default.
        public let q10: Double
        public let fitted: Bool

        /// When the starter fed at `fedAt` will be ripe.
        public func readyDate(fedAt: Date) -> Date {
            fedAt.addingTimeInterval(TimeInterval(minutes * 60))
        }
    }

    /// The estimate for `temperature` from `observations`, newest first;
    /// nil without any. Only the `recentCount` newest count.
    public static func estimate(from observations: [Observation], at temperature: Double) -> Estimate? {
        let recent = observations.filter { $0.peakMinutes > 0 }.prefix(recentCount)
        guard !recent.isEmpty else { return nil }

        let (q10, fitted) = fittedQ10(recent) ?? (defaultQ10, false)

        // Every feeding as it would have run at the reference temperature.
        let atReference = recent.map { observation in
            Double(observation.peakMinutes) * pow(q10, (observation.temperature - referenceTemperature) / 10)
        }
        let typical = median(atReference)
        let minutes = typical * pow(q10, (referenceTemperature - temperature) / 10)

        return Estimate(minutes: max(5, Int((minutes / 5).rounded()) * 5),
                        temperature: temperature,
                        observations: recent.count,
                        q10: q10,
                        fitted: fitted)
    }

    /// The factor per 10 °C this starter shows, from the slope of log time
    /// over temperature; nil when the feedings are too few or too alike in
    /// temperature to tell.
    static func fittedQ10<C: Collection>(_ observations: C) -> (Double, Bool)? where C.Element == Observation {
        guard observations.count >= fitMinimumCount,
              let coldest = observations.map(\.temperature).min(),
              let warmest = observations.map(\.temperature).max(),
              warmest - coldest >= fitMinimumSpan else { return nil }

        let points = observations.map { (x: $0.temperature, y: log(Double($0.peakMinutes))) }
        let n = Double(points.count)
        let meanX = points.map(\.x).reduce(0, +) / n
        let meanY = points.map(\.y).reduce(0, +) / n
        let covariance = points.map { ($0.x - meanX) * ($0.y - meanY) }.reduce(0, +)
        let variance = points.map { ($0.x - meanX) * ($0.x - meanX) }.reduce(0, +)
        guard variance > 0 else { return nil }

        // ln t = a + b·T, and t halves every 10/ln(q10) degrees: q10 = e^(−10b).
        let slope = covariance / variance
        let q10 = exp(-10 * slope)
        return (min(max(q10, q10Range.lowerBound), q10Range.upperBound), true)
    }

    /// The step of a starter recipe that is the ripening: the longest one.
    /// Nil for a recipe without steps or without any duration.
    public static func ripeningStepIndex(durations: [Int]) -> Int? {
        guard let longest = durations.max(), longest > 0 else { return nil }
        return durations.firstIndex(of: longest)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
