//
//  DurationInput.swift
//  BakePlannerCore
//
//  Durations are stored in minutes, but nobody thinks of a 14-hour cold
//  proof as 840. This reads what a baker writes — "90", "1:30", "1h 30",
//  "1,5 h", "45 min", "14 Std" — and keeps the minutes. Moved from the iOS
//  app (DurationField.swift) so Android reads durations the same way.
//

import Foundation

/// Reading and writing a duration as text.
public enum DurationInput {

    // "1:30", "0:45", "14:00" — hours and minutes with a colon.
    private static let clockExpression = try? NSRegularExpression(pattern: #"^(\d{1,3}):(\d{1,2})$"#)
    // "1h", "1 h", "1,5 h", "2 Std.", "14 Stunden", "2 hours", "3 heures".
    // No word boundary after the unit: in "1h30" a digit follows the h.
    private static let hoursExpression = try? NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)\s*(?:h|hr|hrs|std\.?|stunden?|hours?|heures?)(?![a-z])"#,
        options: [.caseInsensitive])
    // "30m", "30 min", "30 Min.", "30 Minuten", "30 minutes".
    private static let minutesExpression = try? NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)\s*(?:m|min\.?|mins|minuten?|minutes?)(?![a-z])"#,
        options: [.caseInsensitive])

    /// The minutes a text stands for; nil while it is not a duration yet
    /// (a lone "1h" is one, a lone "-" is not). An empty text is zero.
    ///
    /// A bare number is minutes. A number with a decimal point or comma
    /// and no unit is hours, since nobody writes fractional minutes. After
    /// an hours part, a bare number is the minutes: "1h 30".
    public static func minutes(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }

        if let whole = Int(trimmed) {
            return whole >= 0 ? whole : nil
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if let match = clockExpression?.firstMatch(in: trimmed, range: range),
           let hoursRange = Range(match.range(at: 1), in: trimmed),
           let minutesRange = Range(match.range(at: 2), in: trimmed),
           let hours = Int(trimmed[hoursRange]),
           let minutes = Int(trimmed[minutesRange]) {
            return hours * 60 + minutes
        }

        if let hours = decimal(trimmed) {
            return hours >= 0 ? Int((hours * 60).rounded()) : nil
        }

        var total = 0.0
        var remainder = trimmed
        var foundUnit = false

        for (expression, factor) in [(hoursExpression, 60.0), (minutesExpression, 1.0)] {
            guard let expression else { continue }
            let matches = expression.matches(in: remainder, range: NSRange(remainder.startIndex..., in: remainder))
            for match in matches.reversed() {
                guard let numberRange = Range(match.range(at: 1), in: remainder),
                      let number = decimal(String(remainder[numberRange])),
                      let matchRange = Range(match.range, in: remainder)
                else { continue }
                total += number * factor
                foundUnit = true
                remainder.replaceSubrange(matchRange, with: " ")
            }
        }

        let leftover = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leftover.isEmpty {
            // "1h 30": the bare number after the hours is minutes.
            guard foundUnit, let bareMinutes = Int(leftover) else { return nil }
            total += Double(bareMinutes)
        }
        guard foundUnit else { return nil }
        return Int(total.rounded())
    }

    /// The text shown for a duration: "45 min", "2 h", "1 h 30 min"; zero
    /// shows as an empty field. Reads back as the same minutes.
    public static func text(forMinutes minutes: Int) -> String {
        guard minutes > 0 else { return "" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        if rest == 0 { return "\(hours) h" }
        return "\(hours) h \(rest) min"
    }

    private static func decimal(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
