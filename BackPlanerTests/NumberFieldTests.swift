//
//  NumberFieldTests.swift
//  BackPlanerTests
//
//  The number ↔ text rules behind NumberField. The field itself needs a
//  keyboard; what makes every digit deletable is that an empty text is a
//  valid number (zero) and a half-typed text leaves the number alone.
//

import Testing
@testable import BackPlaner

@Suite("Number field: text to number and back")
struct NumberFieldTests {

    @Test("An empty field is zero, so the last digit may go")
    func emptyIsZero() {
        #expect(Int.parseField("") == 0)
        #expect(Int.parseField("  ") == 0)
        #expect(Double.parseField("") == 0)
    }

    @Test("Whole numbers", arguments: [("12", 12), ("0", 0), (" 7 ", 7), ("1,5", 1), ("1.5", 1)])
    func wholeNumbers(text: String, expected: Int) {
        #expect(Int.parseField(text) == expected)
    }

    @Test("Decimals with either separator", arguments: [("1,5", 1.5), ("1.5", 1.5), ("500", 500), ("0,25", 0.25)])
    func decimals(text: String, expected: Double) {
        #expect(Double.parseField(text) == expected)
    }

    @Test("A half-typed number is not a number yet", arguments: ["-", "abc", "1,5,"])
    func notYetANumber(text: String) {
        #expect(Double.parseField(text) == nil)
        #expect(Int.parseField(text) == nil)
    }

    @Test("Zero shows as an empty field, other values as plain digits")
    func fieldText() {
        #expect(Int.fieldText(for: 0) == "")
        #expect(Int.fieldText(for: 12) == "12")
        #expect(Double.fieldText(for: 0) == "")
        #expect(Double.fieldText(for: 500) == "500")
        // No grouping separator, whatever the locale: "1000", not "1.000".
        #expect(Double.fieldText(for: 1000) == "1000")
        #expect(Int.fieldText(for: 1000) == "1000")
    }

    @Test("What is shown reads back as the same value")
    func roundTrip() {
        for value in [0.5, 1.5, 12.25, 500, 1000, 2.125] {
            #expect(Double.parseField(Double.fieldText(for: value)) == value)
        }
    }
}
