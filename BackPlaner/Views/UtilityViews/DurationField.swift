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

// DurationInput (reading and writing a duration as text) lives in BakePlannerCore.

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
