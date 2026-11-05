//
//  RecipeVariants.swift
//  BakePlannerCore
//
//  What both apps share about recipe variants, so it is decided once: how a
//  variant is named ("Landbrot V1", "Landbrot V2", …) and the line that says
//  how often and how well a variant baked.
//

import Foundation

extension AdjustedRecipe {

    /// The suffix a variant's name ends in: a space, "V" and a number.
    private static let variantSuffix = #"\sV(\d+)$"#

    /// "Landbrot" for "Landbrot V2", and for "Landbrot" itself: the name a
    /// recipe and its variants share.
    public static func familyName(of name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let range = trimmed.range(of: variantSuffix, options: .regularExpression) else { return trimmed }
        return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    /// 2 for "Landbrot V2"; nil for a name without the suffix.
    public static func variantNumber(of name: String) -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let range = trimmed.range(of: variantSuffix, options: .regularExpression) else { return nil }
        return Int(trimmed[range].drop { !$0.isNumber })
    }

    /// "Landbrot V3": the name of a new variant of `original`, numbered after
    /// every recipe of the same family among `existingNames` — all of the
    /// user's recipes. A number is never handed out twice, so a deleted V2
    /// does not come back under another recipe, and a variant made from
    /// "Landbrot V1" joins the family as "Landbrot V3", not "Landbrot V1 V1".
    /// The variant knows its origin, its note says what it changes and the
    /// history says when it baked, so the name carries none of that any more.
    public static func variantName(original: String, among existingNames: [String]) -> String {
        let family = familyName(of: original)
        let highest = existingNames
            .filter { familyName(of: $0) == family }
            .compactMap(variantNumber(of:))
            .max() ?? 0
        return "\(family) V\(highest + 1)"
    }
}

public enum RecipeVariantText {
    /// "3-mal gebacken · zuletzt 12.10.2026: ★★★★ · offen" for a variant
    /// baked `completedCount` times, the last time on `lastDateText` with
    /// the facts in `lastFactsLine`; "Noch nicht gebacken" for none.
    public static func bakes(completedCount: Int, lastDateText: String, lastFactsLine: String,
                             bundle: Bundle = AppSettings.localizationBundle) -> String {
        guard completedCount > 0 else {
            return String(localized: "Noch nicht gebacken", bundle: bundle)
        }
        var last = lastDateText
        if !lastFactsLine.isEmpty { last += ": " + lastFactsLine }
        return String(localized: "\(completedCount)-mal gebacken", bundle: bundle)
            + " · " + String(localized: "zuletzt \(last)", bundle: bundle)
    }
}
