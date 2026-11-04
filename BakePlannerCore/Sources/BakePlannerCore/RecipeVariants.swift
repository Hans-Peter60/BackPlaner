//
//  RecipeVariants.swift
//  BakePlannerCore
//
//  The texts both apps show for recipe variants, so they are worded once
//  and translated once: the name of a variant made by hand, and the line
//  that says how often and how well a variant baked.
//

import Foundation

extension AdjustedRecipe {
    /// The name of a variant made by hand: "Landbrot – Variante (04.11.2026)",
    /// the dated form every copy of a recipe carries.
    public static func variantName(original: String, on date: Date = Date()) -> String {
        name(original: original,
             adjustment: String(localized: "Variante", bundle: AppSettings.localizationBundle),
             on: date)
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
