//
//  ServingScale.swift
//  BakePlannerCore
//
//  Two rules both apps share when a recipe is shown at another amount: the
//  scale from a portion factor or a target dough weight, and the baker's
//  percentages behind the ingredient lines. Moved from the iOS app
//  (AdaptiveLayout.swift, TotalIngredientsView.swift) so Android shows the
//  same numbers.
//

import Foundation

/// The scale a recipe is shown at, from either of two inputs.
public enum ServingScale {

    /// A target dough weight wins over the picker; without one the picker's
    /// half steps apply (2 = 1.0).
    public static func factor(servingSize: Int, targetWeight: Int?, baseWeight: Double) -> Double {
        if let targetWeight, targetWeight > 0, baseWeight > 0 {
            return Double(targetWeight) / baseWeight
        }
        return Double(servingSize) / 2
    }
}

/// Baker's percentages: every ingredient of a component as a share of that
/// component's flour, which is how bakers compare and scale formulas. Flour
/// is recognised by name; a component without any shows no percentages.
public enum BakersPercentage {

    /// The same flour the dough yield counts, so the two never disagree.
    public static func isFlour(_ name: String) -> Bool {
        DoughComposition.isFlour(name)
    }

    /// The summed weight of the flours, independent of the scale shown —
    /// percentages do not change with the batch size.
    public static func flourWeight(of ingredients: [TotalIngredientData]) -> Double {
        ingredients.filter { isFlour($0.name) && $0.weight > 0 }.map(\.weight).reduce(0, +)
    }

    /// " · 62 %" for a weighed ingredient; nothing for pieces, for a whole
    /// component used as an ingredient ("1 gesamtes Brühstück", no unit), or
    /// when the component has no flour. Non-breaking spaces keep the
    /// percentage in one piece when a narrow column wraps the line.
    public static func suffix(for ingredient: TotalIngredientData, flourWeight: Double) -> String {
        guard flourWeight > 0, ingredient.weight > 0,
              !ingredient.unit.trimmingCharacters(in: .whitespaces).isEmpty
        else { return "" }
        let percent = (ingredient.weight / flourWeight * 100).rounded()
        guard percent >= 1 else { return "" }
        return " ·\u{00A0}\(Int(percent))\u{00A0}%"
    }
}
