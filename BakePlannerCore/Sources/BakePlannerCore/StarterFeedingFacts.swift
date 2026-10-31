//
//  StarterFeedingFacts.swift
//  BakePlannerCore
//
//  The structured part of a starter-feeding log entry: how long it took to
//  peak, and whether it passed the float test. Both stay optional — a
//  value never measured must read differently from a measured zero or a
//  failed test, which `nil` says and a bare `0`/`false` would not.
//

import Foundation

public struct StarterFeedingFacts: Equatable {

    /// Minutes from feeding to peak rise — the starter's health indicator.
    public var peakMinutes: Int?
    /// `nil` when the float test was not tried.
    public var floatTestPassed: Bool?
    public var note: String = ""

    public init(peakMinutes: Int? = nil, floatTestPassed: Bool? = nil, note: String = "") {
        self.peakMinutes = peakMinutes
        self.floatTestPassed = floatTestPassed
        self.note = note
    }

    /// The facts as every store keeps them: the note trimmed, a peak time
    /// of zero minutes or less as not measured. The float test stays as it
    /// is — a failed test is a result.
    public var normalized: StarterFeedingFacts {
        StarterFeedingFacts(peakMinutes: peakMinutes.flatMap { $0 > 0 ? $0 : nil },
                            floatTestPassed: floatTestPassed,
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func minutesInput(_ minutes: Int?) -> String {
        BakeHistoryFacts.minutesInput(minutes)
    }

    public static func parseMinutes(_ text: String) -> Int? {
        BakeHistoryFacts.parseMinutes(text)
    }
}
