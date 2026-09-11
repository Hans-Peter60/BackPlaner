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
            Text("Gesamtzutaten:")
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

/// One component of a recipe: its name and the ingredients listed under it.
///
/// Exists so the same card can serve both recipe models — the Firebase
/// `ComponentFB` of the public database and the Core Data `Component` of the
/// user's own recipes — without the view knowing either.
struct ComponentColumn: Identifiable {
    let id: String
    let name: String
    let ingredients: [TotalIngredientData]

    /// The components of a recipe from the public database.
    static func columns(of components: [ComponentFB]) -> [ComponentColumn] {
        components
            .sorted { $0.number < $1.number }
            .enumerated()
            .map { index, component in
                ComponentColumn(
                    id: component.id ?? "component-\(index)",
                    name: component.name,
                    ingredients: component.ingredients
                        .sorted { $0.number < $1.number }
                        .map {
                            TotalIngredientData(name: $0.name,
                                                unit: $0.unit,
                                                weight: $0.weight,
                                                numerator: $0.num,
                                                denominator: $0.denom)
                        }
                )
            }
    }

    /// The components of one of the user's own recipes.
    static func columns(of components: [Component]) -> [ComponentColumn] {
        components
            .sorted { $0.number < $1.number }
            .map { component in
                ComponentColumn(
                    id: component.objectID.uriRepresentation().absoluteString,
                    name: component.name,
                    // Already sorted by number by the accessor itself.
                    ingredients: component.ingredientsArray.map {
                        TotalIngredientData(name: $0.name,
                                            unit: $0.unit ?? "",
                                            weight: $0.weight,
                                            numerator: $0.num,
                                            denominator: $0.denom)
                    }
                )
            }
    }
}

/// The recipe's components, each with its own ingredient list, side by side —
/// with "Komponenten:" as the heading of that same card.
///
/// Deliberately a `Grid` and not the `LazyVGrid` this used to be, for two
/// measured reasons.
///
/// A lazy grid reports its size only once its cells have been realised, and
/// inside the `GeometryReader` that wraps the public recipe screens that
/// arrived a layout pass too late: the card had been sized for its heading
/// alone (68 pt), so the heading ended up drawn 80 pt above the list it
/// introduces — inside the ingredients card above it. A recipe has a handful of
/// components, so laziness bought nothing here in the first place.
///
/// And `GridItem(alignment: .leading)` aligns leading *horizontally* while
/// centring vertically, so a two-ingredient column was centred against a
/// seven-ingredient one and the column titles came out on three different
/// lines — measured 72 pt apart on a 13-inch iPad. `Grid`'s `.topLeading`
/// puts them on one line.
struct ComponentColumnsView: View {

    let components: [ComponentColumn]
    let selectedServingSize: Int

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dynamicTypeSize)     private var dynamicTypeSize

    /// How many components stand side by side.
    ///
    /// Three used to be the answer on every device. That is right for an iPad
    /// and too optimistic for an iPhone: 440 pt across, minus the card's
    /// padding and the gaps, leaves about 130 pt per column — narrower than
    /// several real lines. "• 123 g Weizenvollkornmehl" measures 189.5 pt and a
    /// component named "Weizensauerteig" measures 125 pt, which is why it used
    /// to break after "Weizensauertei". Two columns give about 200 pt, enough
    /// for both; at the accessibility text sizes even that is hopeless, so the
    /// components simply stack.
    private var columnCount: Int {
        if dynamicTypeSize.isAccessibilitySize { return 1 }
        return hSize == .regular ? 3 : 2
    }

    /// The components chunked into rows, since a `Grid` needs its rows spelled
    /// out where a `LazyVGrid` wrapped them by itself.
    private var rows: [[ComponentColumn]] {
        stride(from: 0, to: components.count, by: columnCount).map { start in
            Array(components[start ..< min(start + columnCount, components.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Komponenten:")
                .font(Theme.brandFont(16))
                .foregroundColor(Theme.title)
                .padding([.bottom, .top], 5)

            Grid(alignment: .topLeading, horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(row) { component in
                            column(for: component)
                        }

                        // A last row with fewer components keeps the column
                        // widths of a full one instead of stretching its cells.
                        if row.count < columnCount {
                            ForEach(row.count ..< columnCount, id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                            }
                        }
                    }
                }
            }
            .scrollsSidewaysAtLargeText()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func column(for component: ComponentColumn) -> some View {
        VStack(alignment: .leading) {
            Text(component.name)
                .font(Theme.brandFont(16))
                .padding([.bottom, .top], 5)

            VStack(alignment: .leading) {
                ForEach(Array(component.ingredients.enumerated()), id: \.offset) { _, ingredient in
                    Text("• " + Rational.getPortion(unit: ingredient.unit,
                                                    weight: ingredient.weight,
                                                    num: ingredient.numerator,
                                                    denom: ingredient.denominator,
                                                    targetServings: selectedServingSize)
                        + ingredient.name)
                        .font(Theme.bodyFont(15))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
