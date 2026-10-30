//
//  RecipePrintData.swift
//  BackPlaner
//
//  What goes on the printed page of a recipe, as plain strings — the part
//  of the PDF export that knows no platform. RecipePDFExporter renders it.
//

import BakePlannerCore
import Foundation

/// A recipe flattened to strings, so the renderer knows neither Core Data
/// nor Firebase and the export can travel across threads.
struct RecipePrintData: Sendable {

    struct Component: Sendable {
        let name: String
        let lines: [String]
    }

    struct Step: Sendable {
        let number: String
        let text: String
        let duration: String
    }

    let name: String
    let summary: String
    let imageData: Data?
    let totalWeight: Int
    let prepTime: String
    let urlLink: String?
    let totalLines: [String]
    let components: [Component]
    let steps: [Step]

    /// A recipe as plain content, at `scale`.
    init(data recipe: RecipeExportData, scale: Double) {
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

    static func components(from columns: [ComponentColumn], scale: Double) -> [Component] {
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
