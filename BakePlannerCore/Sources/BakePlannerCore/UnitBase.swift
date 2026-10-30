//
//  UnitBase.swift
//  BakePlannerCore
//
//  What a unit's `factor` counts in. The settings add the words they show
//  for it (AppSettings.swift).
//

import Foundation

/// What a unit's `factor` counts in.
///
/// This is the whole reason the unit menu offers a list instead of a text
/// field: a unit in this app is not a label but a conversion rule. "Tas" says
/// 200 ml, "Handvoll" says 25 g, and the ingredient totals, the baker's
/// percentages and the shopping list are all computed from that. A unit
/// without a factor cannot be converted — the amount would be read as grams,
/// so "2 Becher Mehl" would count as 2 g instead of roughly 500.
public enum UnitBase: String, CaseIterable, Identifiable {
    /// The factor is a weight in grams.
    case gram = "g"
    /// The factor is a volume in millilitres; the ingredient's density is
    /// applied on top of it (a cup of flour weighs less than a cup of water).
    case milliliter = "ml"
    /// Counted rather than weighed, like eggs.
    case piece = "St"

    public var id: String { rawValue }
}
