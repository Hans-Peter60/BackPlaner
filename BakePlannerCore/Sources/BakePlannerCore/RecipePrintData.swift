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

        public init(number: String, text: String, duration: String) {
            self.number = number
            self.text = text
            self.duration = duration
        }
    }

    public let name: String
    public let summary: String
    public let imageData: Data?
    public let totalWeight: Int
    public let prepTime: String
    public let urlLink: String?
    public let totalLines: [String]
    public let components: [Component]
    public let steps: [Step]

    /// A recipe as plain content, at `scale`.
    public init(data recipe: RecipeExportData, scale: Double) {
        name = recipe.name
        summary = recipe.summary
        imageData = recipe.image
        totalWeight = Int((recipe.totalWeight * scale).rounded())
        prepTime = Rational.displayHoursMinutes(recipe.prepTime)
        urlLink = recipe.urlLink.flatMap { $0.isEmpty ? nil : $0 }

        let columns = ComponentColumn.columns(of: recipe)
        components = Self.components(from: columns, scale: scale)
        totalLines = TotalIngredientsList.aggregatedLines(of: columns, scale: scale)
        steps = recipe.instructions.map {
            Step(number: Rational.decimalPlace($0.step, 10),
                 text: $0.instruction,
                 duration: Rational.displayHoursMinutes($0.duration))
        }
    }

    /// A recipe from the public database, its picture already as JPEG.
    public init(recipeFB: RecipeFB, imageData: Data?, scale: Double) {
        name = recipeFB.name
        summary = recipeFB.summary
        self.imageData = imageData
        totalWeight = Int((recipeFB.totalWeight * scale).rounded())
        prepTime = Rational.displayHoursMinutes(recipeFB.prepTime)
        urlLink = recipeFB.urlLink.isEmpty ? nil : recipeFB.urlLink

        let columns = ComponentColumn.columns(of: recipeFB.components)
        components = Self.components(from: columns, scale: scale)
        totalLines = TotalIngredientsList.aggregatedLines(of: columns, scale: scale)
        steps = recipeFB.instructions
            .sorted { $0.step < $1.step }
            .map {
                Step(number: Rational.decimalPlace($0.step, 10),
                     text: $0.instruction,
                     duration: Rational.displayHoursMinutes($0.duration))
            }
    }

    public static func components(from columns: [ComponentColumn], scale: Double) -> [Component] {
        columns.map { column in
            Component(
                name: column.name,
                lines: column.ingredients.map { ingredient in
                    "• " + Rational.getPortion(unit: ingredient.unit,
                                               weight: ingredient.weight,
                                               num: ingredient.numerator,
                                               denom: ingredient.denominator,
                                               scale: scale)
                        + ingredient.name.trimmingCharacters(in: .whitespaces)
                }
            )
        }
    }
}
