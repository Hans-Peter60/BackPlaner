//
//  KitchenPortions.swift
//  BakePlannerCore
//
//  A CookPlanner dish cooked for more or fewer people than the recipe says.
//  Only the amounts change: the steps keep their minutes, since chopping
//  for six is planned the way the cook knows it, and the learned times
//  come from the stopwatch.
//

import Foundation

public enum KitchenPortions {

    /// The factors offered when the recipe does not say for how many.
    public static let factors: [Double] = [0.5, 1, 1.5, 2, 2.5, 3, 4]

    /// The factor that turns the recipe's servings into `servings`; 1 when
    /// either is unknown or not positive.
    public static func factor(servings: Int, base: Int?) -> Double {
        guard let base, base > 0, servings > 0 else { return 1 }
        return Double(servings) / Double(base)
    }

    /// Units that count things: you take half an onion, not 0.37 of one.
    static let countedUnits: Set<String> = [
        "", "stück", "stk", "stk.", "st", "st.", "zehe", "zehen", "zweig", "zweige", "bund", "dose", "dosen",
        "scheibe", "scheiben", "blatt", "blätter", "prise", "prisen", "ei", "eier", "pck", "pck.", "päckchen",
        "el", "tl", "msp", "msp.", "handvoll", "becher", "glas", "knolle", "stange", "stangen",
        "piece", "pieces", "clove", "cloves", "sprig", "sprigs", "bunch", "can", "slice", "slices", "pinch",
        "tbsp", "tsp", "cup", "cups",
    ]

    /// `amount` scaled by `factor` and rounded the way one measures it:
    /// counted units to halves, below half a piece to quarters — a quarter
    /// teaspoon halved stays a quarter rather than doubling to a half —,
    /// grams and millilitres to a sensible step for their size.
    public static func scaled(_ amount: Double, unit: String, by factor: Double) -> Double {
        guard factor > 0, factor != 1 else { return amount }
        let raw = amount * factor
        if countedUnits.contains(unit.lowercased().trimmingCharacters(in: .whitespaces)) {
            if raw < 0.5 { return max(0.25, (raw * 4).rounded() / 4) }
            return (raw * 2).rounded() / 2
        }
        let step: Double
        switch raw {
        case 500...: step = 10
        case 100..<500: step = 5
        case 10..<100: step = 1
        case 1..<10: step = 0.5
        default: step = 0.05
        }
        return max(step, (raw / step).rounded() * step)
    }
}

extension KitchenDish {

    /// The dish with its ingredient amounts scaled by `factor`; the steps,
    /// ids and everything else stay as they are.
    public func scaled(by factor: Double) -> KitchenDish {
        guard factor > 0, factor != 1 else { return self }
        var copy = self
        copy.ingredients = ingredients.map { ingredient in
            var scaled = ingredient
            scaled.amount = ingredient.amount.map { KitchenPortions.scaled($0, unit: ingredient.unit, by: factor) }
            return scaled
        }
        return copy
    }
}
