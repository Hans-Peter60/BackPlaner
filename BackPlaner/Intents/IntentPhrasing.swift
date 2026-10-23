//
//  IntentPhrasing.swift
//  BackPlaner
//
//  The words Siri uses for a point in time and a planned step. Siri speaks
//  the system language, so unlike the in-app texts these resolve through
//  the main bundle and the current locale rather than the language picked
//  inside the app — a dialog half in one language and half in the other
//  would be worse than either.
//

import Foundation

enum IntentPhrasing {

    /// "heute um 14:30", "morgen um 06:15", "gestern um 18:00", or the
    /// weekday with date and time for anything further away.
    static func dateText(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "heute um \(time)")
        }
        if calendar.isDateInTomorrow(date) {
            return String(localized: "morgen um \(time)")
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "gestern um \(time)")
        }
        return String(localized: "am \(date.formatted(.dateTime.weekday(.wide).day().month(.wide))) um \(time)")
    }

    /// A planned step's instruction as one spoken line. A step such as
    /// "Weizensauerteig\nZutaten mischen" carries its component on a line
    /// of its own, which read aloud needs a pause, not a line break.
    static func spokenInstruction(_ instruction: String) -> String {
        instruction
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
