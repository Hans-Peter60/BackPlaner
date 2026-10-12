//
//  StarterFeedingFacts.swift
//  BackPlaner
//
//  The structured part of a starter-feeding log entry: how long it took to
//  peak, and whether it passed the float test. Both stay optional — a
//  value never measured must read differently from a measured zero or a
//  failed test, which `nil` says and a bare `0`/`false` would not.
//

import Foundation
import CoreData

struct StarterFeedingFacts: Equatable {

    /// Minutes from feeding to peak rise — the starter's health indicator.
    var peakMinutes: Int?
    /// `nil` when the float test was not tried.
    var floatTestPassed: Bool?
    var note: String = ""

    init(peakMinutes: Int? = nil, floatTestPassed: Bool? = nil, note: String = "") {
        self.peakMinutes = peakMinutes
        self.floatTestPassed = floatTestPassed
        self.note = note
    }

    static func minutesInput(_ minutes: Int?) -> String {
        BakeHistoryFacts.minutesInput(minutes)
    }

    static func parseMinutes(_ text: String) -> Int? {
        BakeHistoryFacts.parseMinutes(text)
    }
}

// MARK: - Core Data

extension StarterFeedingLog {

    /// Empty texts are stored as `nil`, so an untouched note never counts as
    /// written.
    var facts: StarterFeedingFacts {
        get {
            StarterFeedingFacts(peakMinutes: peakMinutes?.intValue,
                                 floatTestPassed: floatTestPassed?.boolValue,
                                 note: note ?? "")
        }
        set {
            peakMinutes = newValue.peakMinutes.flatMap { $0 > 0 ? NSNumber(value: $0) : nil }
            floatTestPassed = newValue.floatTestPassed.map { NSNumber(value: $0) }
            let note = newValue.note.trimmingCharacters(in: .whitespacesAndNewlines)
            self.note = note.isEmpty ? nil : note
        }
    }
}
