//
//  AdjustedRecipe.swift
//  BackPlaner
//
//  What the flour substitution and the starter adjustment share once they
//  write their result: the name of the copy, and the rule that a copy is
//  changed in place rather than copied again.
//

import BakePlannerCore
import Foundation

enum AdjustedRecipe {

    /// The name of a recipe after an adjustment: the original name, the
    /// adjustments made so far, and the date of the last one.
    ///
    ///     Landbrot                                → Landbrot – Dinkelmehl 630 (14.10.2026)
    ///     Landbrot – Dinkelmehl 630 (14.10.2026)  → Landbrot – Dinkelmehl 630, TA 210 (14.10.2026)
    ///
    /// A recipe that already carries a dated suffix is an adjusted copy; the
    /// new adjustment joins the ones named before it, and the date moves on
    /// to today. The user asked for the date so a copy made for one bake is
    /// told apart from the original and from last month's copy.
    static func name(original: String, adjustment: String, on date: Date = Date()) -> String {
        let trimmed = original.trimmingCharacters(in: .whitespaces)
        let stamp = date.formatted(.dateTime.day().month().year().locale(AppSettings.locale))

        if let range = datedSuffixRange(in: trimmed) {
            let base = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            return "\(base), \(adjustment) (\(stamp))"
        }
        return "\(trimmed) – \(adjustment) (\(stamp))"
    }

    /// Whether the name ends in the dated suffix `name(original:adjustment:on:)`
    /// writes.
    static func hasDatedSuffix(_ name: String) -> Bool {
        datedSuffixRange(in: name.trimmingCharacters(in: .whitespaces)) != nil
    }

    /// The range of a trailing " (…2026…)" — a bracketed chunk holding a
    /// four-digit year, whatever the locale's date format put around it.
    private static func datedSuffixRange(in name: String) -> Range<String.Index>? {
        let pattern = #"\s*\([^()]*\b\d{4}\b[^()]*\)$"#
        return name.range(of: pattern, options: .regularExpression)
    }
}
