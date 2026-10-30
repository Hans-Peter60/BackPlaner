//
//  NumberField.swift
//  BackPlaner
//

import BakePlannerCore
import SwiftUI

/// A text field for a number whose every digit can be deleted.
///
/// `TextField(value:formatter:)` re-formats what is typed the moment the
/// number changes. On the current system that left the first digit of a
/// field undeletable and, once an amount had been changed, no digit at all.
/// Here the text typed stays text: the number follows it on every change
/// (an empty field means zero), and the text is only written back from the
/// number when the field is left or the number is changed from outside,
/// for instance when a row is reset after it was added.
struct NumberField<Value: NumberFieldValue>: View {

    private let title: Text
    @Binding private var value: Value

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(_ titleKey: LocalizedStringKey = "", value: Binding<Value>) {
        self.title = Text(titleKey)
        _value = value
        _text = State(initialValue: Value.fieldText(for: value.wrappedValue))
    }

    /// A plain string as placeholder, kept out of the String Catalog the
    /// way `TextField` keeps one — for purely visual placeholders like ".".
    init<S: StringProtocol>(_ title: S, value: Binding<Value>) {
        self.title = Text(title)
        _value = value
        _text = State(initialValue: Value.fieldText(for: value.wrappedValue))
    }

    var body: some View {
        TextField(text: $text) { title }
            .keyboardType(.decimalPad)
            .focused($isFocused)
            .onChange(of: text) { _, newText in
                // A half-typed "1," is not a number yet and keeps the value
                // the field already had.
                guard let typed = Value.parseField(newText) else { return }
                if typed != value { value = typed }
            }
            .onChange(of: value) { _, newValue in
                // Changed from outside: the text follows, unless it already
                // reads as this value — then it is the user's own typing.
                if Value.parseField(text) != newValue {
                    text = Value.fieldText(for: newValue)
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { text = Value.fieldText(for: value) }
            }
    }
}

/// A number a ``NumberField`` can edit.
protocol NumberFieldValue: Equatable {
    static var zero: Self { get }
    /// The value a text stands for; nil while it is not a number. An empty
    /// field is zero.
    static func parseField(_ text: String) -> Self?
    /// The text shown for a value; zero shows as an empty field.
    static func fieldText(for value: Self) -> String
}

extension Int: NumberFieldValue {
    static func parseField(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        if let whole = Int(trimmed) { return whole }
        return NumberFieldParsing.number(from: trimmed).map { Int($0) }
    }

    static func fieldText(for value: Int) -> String {
        value == 0 ? "" : String(value)
    }
}

extension Double: NumberFieldValue {
    static func parseField(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        return NumberFieldParsing.number(from: trimmed)
    }

    static func fieldText(for value: Double) -> String {
        value == 0 ? "" : (NumberFieldParsing.formatter.string(from: NSNumber(value: value)) ?? String(value))
    }
}

enum NumberFieldParsing {

    /// Plain digits with the locale's decimal separator and no grouping, so
    /// "1000" does not come back as "1.000" when the field is left.
    static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 3
        return formatter
    }()

    /// The locale's own spelling first; a decimal point or comma from the
    /// other convention is accepted as well, since the keyboard offers
    /// whichever the device's region prefers.
    static func number(from text: String) -> Double? {
        if let number = formatter.number(from: text) { return number.doubleValue }
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
}
