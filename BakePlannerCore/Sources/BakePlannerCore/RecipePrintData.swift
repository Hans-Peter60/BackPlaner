//
//  RecipePrintData.swift
//  BakePlannerCore
//
//  What goes on the printed page of a recipe, as plain strings — the part
//  of the PDF export that knows no platform. RecipePDFExporter renders it.
//

import Foundation

/// A recipe flattened to strings, so the renderer knows neither Core Data
/// nor Firebase and the export can travel across threads.
public struct RecipePrintData: Sendable {

    public struct Component: Sendable {
        public let name: String
        public let lines: [String]

        public init(name: String, lines: [String]) {
            self.name = name
            self.lines = lines
        }
    }

    public struct Step: Sendable {
        public let number: String
        public let text: String
        public let duration: String
        /// The step's time window as the tables show it ("12h 00m – 18h
        /// 00m"), when the plan may stretch or shorten the step.
        public let window: String?
        /// The oven's stored settings ("250 °C, fallend auf 220 °C, mit
        /// Schwaden"), when the step has any.
        public let oven: String?

        public init(number: String, text: String, duration: String, window: String? = nil, oven: String? = nil) {
            self.number = number
            self.text = text
            self.duration = duration
            self.window = window
            self.oven = oven
        }
    }

    public let name: String
    public let summary: String
    public var imageData: Data?
    public let totalWeight: Int
    public let prepTime: String
    public let urlLink: String?
    public let totalLines: [String]
    public let components: [Component]
    public let steps: [Step]

    /// A recipe as plain content, at `scale`.
    /// `bakersPercentages` appends every weighed ingredient's share of its
    /// component's flour to the line, as the iPhone's setting does.
    public init(data recipe: RecipeExportData, scale: Double, bakersPercentages: Bool = false) {
        name = recipe.name
        summary = recipe.summary
        imageData = recipe.image
        totalWeight = Int((recipe.totalWeight * scale).rounded())
        prepTime = Rational.displayHoursMinutes(recipe.prepTime)
        urlLink = recipe.urlLink.flatMap { $0.isEmpty ? nil : $0 }

        let columns = ComponentColumn.columns(of: recipe)
        components = Self.components(from: columns, scale: scale, bakersPercentages: bakersPercentages)
        totalLines = TotalIngredientsList.aggregatedLines(of: columns, scale: scale)
        steps = recipe.instructions.map {
            Step(number: Rational.decimalPlace($0.step, 10),
                 text: $0.instruction,
                 duration: Rational.displayHoursMinutes($0.duration),
                 window: DurationWindow.effective(stored: $0.durationWindow, instruction: $0.instruction,
                                                  duration: $0.duration).map(DurationWindow.text),
                 oven: $0.oven?.summary())
        }
    }

    /// A recipe from the public database, its picture already as JPEG.
    public init(recipeFB: RecipeFB, imageData: Data?, scale: Double, bakersPercentages: Bool = false) {
        name = recipeFB.name
        summary = recipeFB.summary
        self.imageData = imageData
        totalWeight = Int((recipeFB.totalWeight * scale).rounded())
        prepTime = Rational.displayHoursMinutes(recipeFB.prepTime)
        urlLink = recipeFB.urlLink.isEmpty ? nil : recipeFB.urlLink

        let columns = ComponentColumn.columns(of: recipeFB.components)
        components = Self.components(from: columns, scale: scale, bakersPercentages: bakersPercentages)
        totalLines = TotalIngredientsList.aggregatedLines(of: columns, scale: scale)
        steps = recipeFB.instructions
            .sorted { $0.step < $1.step }
            .map {
                Step(number: Rational.decimalPlace($0.step, 10),
                     text: $0.instruction,
                     duration: Rational.displayHoursMinutes($0.duration),
                     window: DurationWindow.effective(stored: $0.durationWindow, instruction: $0.instruction,
                                                      duration: $0.duration).map(DurationWindow.text),
                     oven: $0.oven?.summary())
            }
    }

    public static func components(from columns: [ComponentColumn], scale: Double,
                                  bakersPercentages: Bool = false) -> [Component] {
        columns.map { column in
            // The flour of the component as stored: percentages do not
            // change with the amount shown.
            let flourWeight = bakersPercentages ? BakersPercentage.flourWeight(of: column.ingredients) : 0
            return Component(
                name: column.name,
                lines: column.ingredients.map { ingredient in
                    "• " + Rational.getPortion(unit: ingredient.unit,
                                               weight: ingredient.weight,
                                               num: ingredient.numerator,
                                               denom: ingredient.denominator,
                                               scale: scale)
                        + ingredient.name.trimmingCharacters(in: .whitespaces)
                        + BakersPercentage.suffix(for: ingredient, flourWeight: flourWeight)
                }
            )
        }
    }
}
