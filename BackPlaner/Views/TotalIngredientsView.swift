import SwiftUI

struct TotalIngredientData {
    let name: String
    let unit: String
    let weight: Double
    let numerator: Int
    let denominator: Int
}

struct TotalIngredientsView: View {
    let ingredients: [TotalIngredientData]
    let componentNames: [String]
    let selectedServingSize: Int

    private var totalIngredients: [TotalIngredient] {
        let normalizedComponentNames = componentNames.map(normalizedProductName)
        let rawIngredients = ingredients.filter { ingredient in
            !isWater(ingredient.name)
                && !isComponentProduct(ingredient, componentNames: normalizedComponentNames)
        }
        return TotalIngredient.aggregate(rawIngredients)
    }

    private func isWater(_ name: String) -> Bool {
        let normalizedName = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .localizedLowercase

        return normalizedName.contains("wasser") || normalizedName.contains("water")
    }

    private func isComponentProduct(
        _ ingredient: TotalIngredientData,
        componentNames: [String]
    ) -> Bool {
        let ingredientName = normalizedProductName(ingredient.name)

        if componentNames.contains(ingredientName) {
            return true
        }

        let representsWholeProduct = ingredient.weight == 0
            && ingredient.denominator != 0
            && ingredient.numerator == ingredient.denominator

        guard representsWholeProduct else {
            return false
        }

        return componentNames.contains { componentName in
            let shortestNameLength = min(ingredientName.count, componentName.count)
            return shortestNameLength >= 5
                && (ingredientName.contains(componentName) || componentName.contains(ingredientName))
        }
    }

    private func normalizedProductName(_ name: String) -> String {
        var normalizedName = IngredientNameNormalizer.comparisonKey(name)

        for prefix in ["gesamter ", "gesamte ", "gesamtes ", "ganzer ", "ganze ", "ganzes "] where normalizedName.hasPrefix(prefix) {
            normalizedName.removeFirst(prefix.count)
            break
        }

        if let separatorIndex = normalizedName.firstIndex(where: { "/(".contains($0) }) {
            normalizedName = String(normalizedName[..<separatorIndex])
        }

        if let stageRange = normalizedName.range(of: " stufe ") {
            normalizedName = String(normalizedName[..<stageRange.lowerBound])
        }

        return normalizedName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gesamtzutaten")
                .font(Theme.brandFont(16))
                .foregroundColor(Theme.title)

            ForEach(totalIngredients) { ingredient in
                Text(
                    "• " + Rational.getPortion(
                        unit: ingredient.unit,
                        weight: ingredient.weight,
                        num: ingredient.numerator,
                        denom: ingredient.denominator,
                        targetServings: selectedServingSize
                    ) + ingredient.name
                )
                .font(Theme.bodyFont(15))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

private struct TotalIngredient: Identifiable {
    let id: String
    let name: String
    let unit: String
    let weight: Double
    let numerator: Int
    let denominator: Int

    static func aggregate(_ ingredients: [TotalIngredientData]) -> [TotalIngredient] {
        var grouped: [String: Accumulator] = [:]

        for ingredient in ingredients {
            let normalizedName = IngredientNameNormalizer.displayName(ingredient.name)
            let normalizedUnit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedName.localizedLowercase + "|" + normalizedUnit.localizedLowercase

            var accumulator = grouped[key] ?? Accumulator(
                name: normalizedName,
                unit: normalizedUnit
            )
            accumulator.add(
                weight: ingredient.weight,
                numerator: ingredient.numerator,
                denominator: ingredient.denominator
            )
            grouped[key] = accumulator
        }

        return grouped.map { key, accumulator in
            accumulator.ingredient(id: key)
        }
        .sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

private struct Accumulator {
    let name: String
    let unit: String
    private var decimalAmount = 0.0
    private var fractionNumerator = 0
    private var fractionDenominator = 1

    mutating func add(weight: Double, numerator: Int, denominator: Int) {
        if weight != 0 {
            decimalAmount += weight
        } else if numerator != 0, denominator != 0 {
            fractionNumerator = fractionNumerator * denominator + numerator * fractionDenominator
            fractionDenominator *= denominator

            let divisor = greatestCommonDivisor(abs(fractionNumerator), abs(fractionDenominator))
            fractionNumerator /= divisor
            fractionDenominator /= divisor
        }
    }

    func ingredient(id: String) -> TotalIngredient {
        if decimalAmount != 0 {
            let combinedAmount = decimalAmount + Double(fractionNumerator) / Double(fractionDenominator)
            return TotalIngredient(
                id: id,
                name: name,
                unit: unit,
                weight: combinedAmount,
                numerator: 0,
                denominator: 0
            )
        }

        return TotalIngredient(
            id: id,
            name: name,
            unit: unit,
            weight: 0,
            numerator: fractionNumerator,
            denominator: fractionDenominator
        )
    }

    private func greatestCommonDivisor(_ first: Int, _ second: Int) -> Int {
        var a = first
        var b = second

        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }

        return max(a, 1)
    }
}
