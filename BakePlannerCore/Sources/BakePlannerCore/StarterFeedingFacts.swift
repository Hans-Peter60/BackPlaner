//
//  StarterFeedingFacts.swift
//  BakePlannerCore
//
//  The structured part of a starter-feeding log entry: how long it took to
//  peak, at what room temperature, and whether it passed the float test.
//  All stay optional — a value never measured must read differently from a
//  measured zero or a failed test, which `nil` says and a bare `0`/`false`
//  would not.
//

import Foundation

public struct StarterFeedingFacts: Equatable {

    /// Minutes from feeding to peak rise — the starter's health indicator.
    public var peakMinutes: Int?
    /// `nil` when the float test was not tried.
    public var floatTestPassed: Bool?
    public var note: String = ""
    /// The room temperature during this feeding in °C, for the ripeness
    /// estimate (StarterRipeness); `nil` when not noted.
    public var roomTemperature: Double?

    public init(peakMinutes: Int? = nil, floatTestPassed: Bool? = nil, note: String = "",
                roomTemperature: Double? = nil) {
        self.peakMinutes = peakMinutes
        self.floatTestPassed = floatTestPassed
        self.note = note
        self.roomTemperature = roomTemperature
    }

    /// Room temperatures a kitchen can have; anything else is a typing slip.
    public static let roomTemperatureRange = -10.0...50.0

    /// The facts as every store keeps them: the note trimmed, a peak time
    /// of zero minutes or less as not measured, a temperature no kitchen
    /// has as not noted. The float test stays as it is — a failed test is a
    /// result.
    public var normalized: StarterFeedingFacts {
        StarterFeedingFacts(peakMinutes: peakMinutes.flatMap { $0 > 0 ? $0 : nil },
                            floatTestPassed: floatTestPassed,
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                            roomTemperature: roomTemperature.flatMap { Self.roomTemperatureRange.contains($0) ? $0 : nil })
    }

    /// The feedings of a diary (newest first) that measured both peak time
    /// and temperature, as StarterRipeness reads them.
    public static func ripenessObservations(_ feedings: [StarterFeedingFacts]) -> [StarterRipeness.Observation] {
        feedings.compactMap { facts in
            guard let minutes = facts.peakMinutes, minutes > 0, let temperature = facts.roomTemperature else { return nil }
            return StarterRipeness.Observation(temperature: temperature, peakMinutes: minutes)
        }
    }

    public static func minutesInput(_ minutes: Int?) -> String {
        BakeHistoryFacts.minutesInput(minutes)
    }

    public static func parseMinutes(_ text: String) -> Int? {
        BakeHistoryFacts.parseMinutes(text)
    }
}
