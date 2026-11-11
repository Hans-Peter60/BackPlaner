//
//  BakersFormula.swift
//  BakePlannerCore
//
//  A recipe written the baker's way: every ingredient as a share of the
//  flour, all the flours together 100 %. Given the flour weight — or the
//  dough weight wanted — the formula becomes a recipe in grams. Shared by
//  the apps; the forms differ, the arithmetic does not.
//

import Foundation

public struct BakersFormula: Equatable, Sendable {

    /// One ingredient with its share of the recipe's whole flour.
    public struct Line: Identifiable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        /// Percent of the recipe's whole flour.
        public var percent: Double

        public init(id: UUID = UUID(), name: String, percent: Double) {
            self.id = id
            self.name = name
            self.percent = percent
        }

        /// Whether the line counts towards the 100 % flour, by its name —
        /// the same reading as the TA breakdown and the baker's percentages
        /// on the recipe page.
        public var isFlour: Bool { DoughComposition.isFlour(name) }

        var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
        var isBlank: Bool { trimmedName.isEmpty }
    }

    /// A dough of the recipe — Vorteig, Sauerteig, Hauptteig — with its lines.
    public struct Component: Identifiable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var lines: [Line]

        public init(id: UUID = UUID(), name: String, lines: [Line]) {
            self.id = id
            self.name = name
            self.lines = lines
        }
    }

    public var components: [Component]

    public init(components: [Component]) {
        self.components = components
    }

    /// The usual start: one main dough of flour, water, salt and yeast.
    public static func template(bundle: Bundle = AppSettings.localizationBundle) -> BakersFormula {
        // Spelled out per key: Skip's Foundation has no String.LocalizationValue
        // to pass around.
        let locale = AppSettings.locale
        return BakersFormula(components: [
            Component(name: String(localized: "Hauptteig", bundle: bundle, locale: locale), lines: [
                Line(name: String(localized: "Weizenmehl 550", bundle: bundle, locale: locale), percent: 100),
                Line(name: String(localized: "Wasser", bundle: bundle, locale: locale), percent: 68),
                Line(name: String(localized: "Salz", bundle: bundle, locale: locale), percent: 2),
                Line(name: String(localized: "Frischhefe", bundle: bundle, locale: locale), percent: 1),
            ]),
        ])
    }

    /// The lines that count: those with a name.
    public var lines: [Line] { components.flatMap(\.lines).filter { !$0.isBlank } }

    /// What the flour lines add up to; a complete formula has 100.
    public var flourPercent: Double { lines.filter(\.isFlour).reduce(0) { $0 + $1.percent } }

    /// Every line together — the dough as a share of the flour.
    public var totalPercent: Double { lines.reduce(0) { $0 + $1.percent } }

    /// What keeps the formula from becoming a recipe.
    public enum Issue: Equatable, Sendable {
        /// No line reads as a flour.
        case noFlour
        /// The flours add up to this, not to 100.
        case flourNot100(Double)
        /// A named line has no share.
        case nonPositive(String)
        case noLines
    }

    public var issues: [Issue] {
        var issues: [Issue] = []
        let lines = self.lines
        if lines.isEmpty { return [.noLines] }
        if !lines.contains(where: \.isFlour) {
            issues.append(.noFlour)
        } else if abs(flourPercent - 100) > 0.05 {
            issues.append(.flourNot100(flourPercent))
        }
        issues += lines.filter { $0.percent <= 0 }.map { .nonPositive($0.trimmedName) }
        return issues
    }

    public var isComplete: Bool { issues.isEmpty }

    /// The flour that gives `dough` grams of dough.
    public func totalFlour(forDoughWeight dough: Double) -> Double {
        totalPercent > 0 ? dough * 100 / totalPercent : 0
    }

    /// The dough that `flour` grams of flour give.
    public func doughWeight(forTotalFlour flour: Double) -> Double {
        flour * totalPercent / 100
    }

    /// Grams of a share at `totalFlour`, rounded the way a kitchen scale
    /// reads: whole grams from 10 g, tenths below — 2 % salt of 500 g is
    /// 10 g, 0.7 % yeast of 500 g is 3.5 g.
    public static func grams(percent: Double, totalFlour: Double) -> Double {
        let exact = totalFlour * percent / 100
        return exact >= 10 ? exact.rounded() : (exact * 10).rounded() / 10
    }

    public func grams(of line: Line, totalFlour: Double) -> Double {
        Self.grams(percent: line.percent, totalFlour: totalFlour)
    }

    /// The recipe in grams: the named lines of every component as
    /// ingredients, one mixing step per component so the plan knows what
    /// goes where. The person adds the rest of the steps in the editor.
    @MainActor
    public func makeRecipe(name: String, totalFlour: Double,
                           bundle: Bundle = AppSettings.localizationBundle) -> RecipeFB {
        let recipe = RecipeFB()
        recipe.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let mainDough = String(localized: "Hauptteig", bundle: bundle, locale: AppSettings.locale)

        recipe.components = components.enumerated().compactMap { index, source in
            let lines = source.lines.filter { !$0.isBlank }
            guard !lines.isEmpty else { return nil }
            let component = ComponentFB()
            component.id = UUID().uuidString
            component.number = index + 1
            let componentName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
            component.name = componentName.isEmpty ? mainDough : componentName
            component.ingredients = lines.enumerated().map { lineIndex, line in
                let ingredient = IngredientFB()
                ingredient.id = UUID().uuidString
                ingredient.number = lineIndex + 1
                ingredient.name = line.trimmedName
                ingredient.weight = grams(of: line, totalFlour: totalFlour)
                ingredient.normWeight = ingredient.weight
                ingredient.unit = "g"
                return ingredient
            }
            return component
        }

        let stepFormat = String(localized: "%@ herstellen", bundle: bundle, locale: AppSettings.locale)
        recipe.instructions = recipe.components.enumerated().map { index, component in
            let instruction = InstructionFB()
            instruction.id = UUID().uuidString
            instruction.step = Double(index + 1)
            instruction.instruction = String(format: stepFormat, locale: AppSettings.locale, component.name)
            instruction.duration = 10
            instruction.componentName = component.name
            instruction.bakeFlag = false
            return instruction
        }

        recipe.totalWeight = recipe.components.flatMap(\.ingredients).reduce(0) { $0 + $1.weight }
        return recipe
    }
}
