//
//  DurationField.swift
//  BackPlaner
//
//  Durations are stored in minutes, but nobody thinks of a 14-hour cold
//  proof as 840. The field takes what a baker writes — "90", "1:30",
//  "1h 30", "1,5 h", "45 min", "14 Std" — and keeps the minutes.
//

import BakePlannerCore
import SwiftUI

/// Reading and writing a duration as text.
enum DurationInput {

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
    static func minutes(from text: String) -> Int? {
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
    static func text(forMinutes minutes: Int) -> String {
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

/// A text field for a duration in minutes that accepts hours as well.
///
/// Like ``NumberField``, the text typed stays text: the minutes follow it
/// on every change, and the text is only written back from the minutes
/// when the field is left or the minutes change from outside.
struct DurationField: View {

    @Binding private var minutes: Int

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(minutes: Binding<Int>) {
        _minutes = minutes
        _text = State(initialValue: DurationInput.text(forMinutes: minutes.wrappedValue))
    }

    var body: some View {
        // The punctuation keyboard has the colon for "1:30" and a key to
        // the letters for "h" and "min".
        TextField(text: $text) {
            Text("min · h:mm")
        }
        .keyboardType(.numbersAndPunctuation)
        .autocorrectionDisabled()
        .focused($isFocused)
        .onChange(of: text) { _, newText in
            guard let typed = DurationInput.minutes(from: newText) else { return }
            if typed != minutes { minutes = typed }
        }
        .onChange(of: minutes) { _, newValue in
            if DurationInput.minutes(from: text) != newValue {
                text = DurationInput.text(forMinutes: newValue)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { text = DurationInput.text(forMinutes: minutes) }
        }
    }
}
