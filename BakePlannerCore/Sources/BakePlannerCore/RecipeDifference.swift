//
//  RecipeDifference.swift
//  BakePlannerCore
//
//  What is different between two recipes — a variant and its origin, or any
//  two recipes the user wants to compare: ingredients replaced, added,
//  removed or weighed differently, components that came or went, the dough
//  yield and hydration before and after, steps whose duration or text
//  changed. Computed on the recipe content as a value (RecipeExportData),
//  so the iPhone and Android read the same lines.
//

import Foundation

public struct RecipeDifference: Equatable {

    public enum ComponentChange: Equatable {
        case added(String)
        case removed(String)
        case renamed(from: String, to: String)
    }

    public enum IngredientChange: Equatable {
        /// "Dinkelmehl 630 statt Weizenmehl 1050 (500 g)" — the flour
        /// substitution's signature.
        case replaced(component: String, from: String, to: String, amount: String)
        case added(component: String, amount: String, name: String)
        case removed(component: String, amount: String, name: String)
        case amountChanged(component: String, name: String, from: String, to: String)
    }

    public enum StepChange: Equatable {
        case durationChanged(step: Double, text: String, fromMinutes: Int, toMinutes: Int)
        case textChanged(step: Double, from: String, to: String)
        case added(step: Double, text: String)
        case removed(step: Double, text: String)
    }

    /// The dough as a whole, before and after; nil for a figure that did not
    /// change (or could not be computed on either side).
    public struct DoughChange: Equatable {
        public var doughYield: (from: Double, to: Double)?
        public var hydration: (from: Double, to: Double)?
        public var totalWeight: (from: Double, to: Double)?

        public var isEmpty: Bool { doughYield == nil && hydration == nil && totalWeight == nil }

        public static func == (lhs: DoughChange, rhs: DoughChange) -> Bool {
            lhs.doughYield?.from == rhs.doughYield?.from && lhs.doughYield?.to == rhs.doughYield?.to
                && lhs.hydration?.from == rhs.hydration?.from && lhs.hydration?.to == rhs.hydration?.to
                && lhs.totalWeight?.from == rhs.totalWeight?.from && lhs.totalWeight?.to == rhs.totalWeight?.to
        }
    }

    public var components: [ComponentChange] = []
    public var ingredients: [IngredientChange] = []
    public var dough = DoughChange()
    public var steps: [StepChange] = []
    /// Whether the recipes have more than one component between them; the
    /// lines then name the component of an ingredient change.
    public var namesComponents = false

    public var isEmpty: Bool {
        components.isEmpty && ingredients.isEmpty && dough.isEmpty && steps.isEmpty
    }

    // MARK: - Computing

    /// The changes from `original` to `variant`.
    public static func between(_ original: RecipeExportData, _ variant: RecipeExportData) -> RecipeDifference {
        var difference = RecipeDifference()
        difference.namesComponents = max(original.components.count, variant.components.count) > 1

        // Components by name; one that went and one that came at the same
        // time is the same component under a new name.
        var pairs: [(RecipeExportComponent, RecipeExportComponent)] = []
        var unmatchedOriginal = original.components
        var unmatchedVariant: [RecipeExportComponent] = []
        for component in variant.components {
            if let index = unmatchedOriginal.firstIndex(where: { sameName($0.name, component.name) }) {
                pairs.append((unmatchedOriginal.remove(at: index), component))
            } else {
                unmatchedVariant.append(component)
            }
        }
        // A component that went and one that came with mostly the same
        // ingredients is the same component under a new name.
        for before in unmatchedOriginal.reversed() {
            guard let index = unmatchedVariant.indices.max(by: { sharedIngredients(before, unmatchedVariant[$0]) < sharedIngredients(before, unmatchedVariant[$1]) }),
                  sharedIngredients(before, unmatchedVariant[index]) >= 0.5 else { continue }
            let after = unmatchedVariant.remove(at: index)
            unmatchedOriginal.removeAll { $0.name == before.name && $0.number == before.number }
            difference.components.append(.renamed(from: before.name, to: after.name))
            pairs.append((before, after))
        }
        difference.components += unmatchedOriginal.map { .removed($0.name) }
        difference.components += unmatchedVariant.map { .added($0.name) }

        for (before, after) in pairs {
            difference.ingredients += ingredientChanges(from: before, to: after, component: after.name)
        }

        difference.dough = doughChange(from: original, to: variant)
        difference.steps = stepChanges(from: original.instructions, to: variant.instructions)
        return difference
    }

    private static func sameName(_ a: String, _ b: String) -> Bool {
        IngredientNameNormalizer.comparisonKey(a) == IngredientNameNormalizer.comparisonKey(b)
    }

    /// The share of `before`'s ingredients that `after` has as well, 0 to 1.
    private static func sharedIngredients(_ before: RecipeExportComponent, _ after: RecipeExportComponent) -> Double {
        guard !before.ingredients.isEmpty else { return 0 }
        let shared = before.ingredients.filter { old in after.ingredients.contains { sameName($0.name, old.name) } }.count
        return Double(shared) / Double(before.ingredients.count)
    }

    private static func ingredientChanges(from before: RecipeExportComponent, to after: RecipeExportComponent,
                                          component: String) -> [IngredientChange] {
        var changes: [IngredientChange] = []
        var remaining = before.ingredients
        var added: [RecipeExportIngredient] = []
        for ingredient in after.ingredients {
            if let index = remaining.firstIndex(where: { sameName($0.name, ingredient.name) }) {
                let old = remaining.remove(at: index)
                if !sameAmount(old, ingredient) {
                    changes.append(.amountChanged(component: component, name: ingredient.name,
                                                  from: amountText(old), to: amountText(ingredient)))
                }
            } else {
                added.append(ingredient)
            }
        }
        // What went and what came in its place: paired by the closest
        // weight, which is how a substitution reads.
        var removed = remaining
        while let new = added.first, !removed.isEmpty {
            added.removeFirst()
            let index = removed.indices.min { abs(removed[$0].normWeight - new.normWeight) < abs(removed[$1].normWeight - new.normWeight) }!
            let old = removed.remove(at: index)
            let amount = sameAmount(old, new) ? amountText(new) : amountText(old) + " → " + amountText(new)
            changes.append(.replaced(component: component, from: old.name, to: new.name, amount: amount))
        }
        changes += removed.map { .removed(component: component, amount: amountText($0), name: $0.name) }
        changes += added.map { .added(component: component, amount: amountText($0), name: $0.name) }
        return changes
    }

    private static func sameAmount(_ a: RecipeExportIngredient, _ b: RecipeExportIngredient) -> Bool {
        abs(a.weight - b.weight) < 0.05 && a.num == b.num && a.denom == b.denom
            && (a.unit ?? "").trimmingCharacters(in: .whitespaces) == (b.unit ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// "500 g", "1/2 TL", "2 Stück" — as the ingredient lines print it.
    static func amountText(_ ingredient: RecipeExportIngredient) -> String {
        Rational.getPortion(unit: ingredient.unit ?? "", weight: ingredient.weight,
                            num: ingredient.num, denom: ingredient.denom, scale: 1)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func doughChange(from original: RecipeExportData, to variant: RecipeExportData) -> DoughChange {
        var change = DoughChange()
        let before = DoughComposition.compute(DoughComposition.components(of: original))
        let after = DoughComposition.compute(DoughComposition.components(of: variant))
        if let before, let after {
            let yieldBefore = before.doughYield.rounded(), yieldAfter = after.doughYield.rounded()
            if yieldBefore != yieldAfter { change.doughYield = (yieldBefore, yieldAfter) }
            let hydrationBefore = (before.hydration * 2).rounded() / 2, hydrationAfter = (after.hydration * 2).rounded() / 2
            if hydrationBefore != hydrationAfter { change.hydration = (hydrationBefore, hydrationAfter) }
        }
        let weightBefore = original.totalWeight.rounded(), weightAfter = variant.totalWeight.rounded()
        if weightBefore != weightAfter { change.totalWeight = (weightBefore, weightAfter) }
        return change
    }

    private static func stepChanges(from original: [RecipeExportInstruction],
                                    to variant: [RecipeExportInstruction]) -> [StepChange] {
        var changes: [StepChange] = []
        var remaining = original
        var unmatched: [RecipeExportInstruction] = []
        // Same wording: the same step, maybe with another duration.
        for step in variant {
            if let index = remaining.firstIndex(where: { stepKey($0.instruction) == stepKey(step.instruction) }) {
                let old = remaining.remove(at: index)
                if old.duration != step.duration {
                    changes.append(.durationChanged(step: step.step, text: step.instruction,
                                                    fromMinutes: old.duration, toMinutes: step.duration))
                }
            } else {
                unmatched.append(step)
            }
        }
        // Same number, other wording: the step was edited.
        var added: [RecipeExportInstruction] = []
        for step in unmatched {
            if let index = remaining.firstIndex(where: { $0.step == step.step }) {
                let old = remaining.remove(at: index)
                changes.append(.textChanged(step: step.step, from: old.instruction, to: step.instruction))
                if old.duration != step.duration {
                    changes.append(.durationChanged(step: step.step, text: step.instruction,
                                                    fromMinutes: old.duration, toMinutes: step.duration))
                }
            } else {
                added.append(step)
            }
        }
        changes += remaining.map { .removed(step: $0.step, text: $0.instruction) }
        changes += added.map { .added(step: $0.step, text: $0.instruction) }
        return changes.sorted { stepNumber($0) < stepNumber($1) }
    }

    private static func stepKey(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stepNumber(_ change: StepChange) -> Double {
        switch change {
        case .durationChanged(let step, _, _, _), .textChanged(let step, _, _), .added(let step, _), .removed(let step, _):
            return step
        }
    }

    // MARK: - Reading

    /// Every change as one line, in the app's language: ingredients first,
    /// then the dough as a whole, then the steps.
    public func lines(bundle: Bundle = AppSettings.localizationBundle) -> [String] {
        var lines: [String] = []
        for change in components {
            switch change {
            case .added(let name):
                lines.append(String(localized: "Neue Komponente „\(name)“", bundle: bundle))
            case .removed(let name):
                lines.append(String(localized: "Komponente „\(name)“ entfällt", bundle: bundle))
            case .renamed(let from, let to):
                lines.append(String(localized: "Komponente „\(from)“ heißt jetzt „\(to)“", bundle: bundle))
            }
        }
        for change in ingredients {
            lines.append(ingredientLine(change, bundle: bundle))
        }
        if let (from, to) = dough.doughYield {
            lines.append(String(localized: "TA \(Self.number(from)) → \(Self.number(to))", bundle: bundle))
        }
        if let (from, to) = dough.hydration {
            // The percent signs travel inside the arguments: a literal one in
            // the key would have to be escaped and escapes the catalog check.
            let fromText = Self.number(from) + " %"
            let toText = Self.number(to) + " %"
            lines.append(String(localized: "Hydration \(fromText) → \(toText)", bundle: bundle))
        }
        if let (from, to) = dough.totalWeight {
            lines.append(String(localized: "Teiggewicht \(Self.number(from)) g → \(Self.number(to)) g", bundle: bundle))
        }
        for change in steps {
            switch change {
            case .durationChanged(let step, _, let from, let to):
                lines.append(String(localized: "Schritt \(Self.stepText(step)): \(DurationInput.text(forMinutes: from)) → \(DurationInput.text(forMinutes: to))", bundle: bundle))
            case .textChanged(let step, _, let to):
                lines.append(String(localized: "Schritt \(Self.stepText(step)) geändert: \(to)", bundle: bundle))
            case .added(let step, let text):
                lines.append(String(localized: "Neuer Schritt \(Self.stepText(step)): \(text)", bundle: bundle))
            case .removed(let step, let text):
                lines.append(String(localized: "Schritt \(Self.stepText(step)) entfällt: \(text)", bundle: bundle))
            }
        }
        return lines
    }

    /// The first changes in one line, for a list row: "Dinkelmehl 630 statt
    /// Weizenmehl 1050 (500 g) · TA 165 → 170"; empty when nothing differs.
    public func summary(maximumItems: Int = 2, bundle: Bundle = AppSettings.localizationBundle) -> String {
        let all = lines(bundle: bundle)
        let shown = all.prefix(maximumItems)
        guard all.count > maximumItems else { return shown.joined(separator: " · ") }
        let more = all.count - maximumItems
        return (shown + [String(localized: "\(more) weitere", bundle: bundle)]).joined(separator: " · ")
    }

    private func ingredientLine(_ change: IngredientChange, bundle: Bundle) -> String {
        switch change {
        case .replaced(let component, let from, let to, let amount):
            return namesComponents
                ? String(localized: "\(component): \(to) statt \(from) (\(amount))", bundle: bundle)
                : String(localized: "\(to) statt \(from) (\(amount))", bundle: bundle)
        case .added(let component, let amount, let name):
            return namesComponents
                ? String(localized: "\(component): neu \(amount) \(name)", bundle: bundle)
                : String(localized: "Neu \(amount) \(name)", bundle: bundle)
        case .removed(let component, let amount, let name):
            return namesComponents
                ? String(localized: "\(component): ohne \(amount) \(name)", bundle: bundle)
                : String(localized: "Ohne \(amount) \(name)", bundle: bundle)
        case .amountChanged(let component, let name, let from, let to):
            return namesComponents
                ? String(localized: "\(component): \(name) \(from) → \(to)", bundle: bundle)
                : String(localized: "\(name) \(from) → \(to)", bundle: bundle)
        }
    }

    /// A step number as the step tables print it: "4", "4.1" — with a
    /// point whatever the language, like the tables.
    static func stepText(_ step: Double) -> String {
        Rational.decimalPlace(step, 10)
    }

    /// 165, 2.1, 72.5 — whole numbers without a decimal, others with the
    /// app language's separator.
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(AppSettings.locale))
    }
}
