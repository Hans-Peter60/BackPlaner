import SwiftUI

struct TotalIngredientsView: View {
    /// The recipe's components with their ingredients. The card needs the
    /// components, not a flat list of ingredients: whether a row stands for
    /// another component depends on which component it is in.
    let components: [ComponentColumn]
    /// 1.0 is the recipe as stored.
    let scale: Double

    private var totalIngredients: [TotalIngredient] {
        Self.totalIngredients(of: components)
    }

    static func totalIngredients(of components: [ComponentColumn]) -> [TotalIngredient] {
        TotalIngredientsList.totalIngredients(of: components)
    }

    static func aggregatedLines(of components: [ComponentColumn], scale: Double) -> [String] {
        TotalIngredientsList.aggregatedLines(of: components, scale: scale)
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
                        scale: scale
                    ) + ingredient.name
                )
                .font(Theme.bodyFont(15))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
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
    /// 1.0 is the recipe as stored.
    let scale: Double
    /// Set by screens that offer the flour substitution: a flour line then
    /// becomes a button reporting its component and ingredient index — the
    /// indices into `components` as handed in.
    var onFlourTap: ((Int, Int) -> Void)? = nil
    /// Set by screens that offer the starter TA adjustment: a starter line
    /// (Anstellgut, Sauerteig, Lievito Madre) then becomes a button the same
    /// way, see StarterYieldAdjustment.
    var onStarterTap: ((Int, Int) -> Void)? = nil

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dynamicTypeSize)     private var dynamicTypeSize

    /// Settings → Rezepte → "Bäckerprozente anzeigen".
    @AppStorage(AppSettingsKeys.bakersPercentages) private var showBakersPercentages = AppSettings.defaultBakersPercentages

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

            if let tapHint {
                Text(tapHint)
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.subtitle)
                    .padding(.bottom, 4)
            }

            Grid(alignment: .topLeading, horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.element.id) { columnIndex, component in
                            column(for: component, at: rowIndex * columnCount + columnIndex)
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
            // Deliberately not `.scrollsSidewaysAtLargeText()`: with a single
            // column at the accessibility sizes there is nothing to scroll
            // to, and the sideways scroll view stopped the ingredient lines
            // from wrapping — "• 213 g Weizenmehl 10" was clipped at the
            // card's edge instead of continuing on the next line.
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var hasFlour: Bool {
        components.contains { $0.ingredients.contains { FlourSubstitution.recognize($0.name) != nil } }
    }

    private var hasStarter: Bool {
        components.contains { $0.ingredients.contains(where: isAdjustableStarter) }
    }

    /// A starter from the jar, not a line that stands for one of this
    /// recipe's own components.
    private func isAdjustableStarter(_ ingredient: TotalIngredientData) -> Bool {
        StarterYieldAdjustment.recognize(ingredient, componentNames: components.map(\.name)) != nil
    }

    /// What tapping a line does, for the one-line hint above the columns.
    private var tapHint: LocalizedStringKey? {
        let flour = onFlourTap != nil && hasFlour
        let starter = onStarterTap != nil && hasStarter
        switch (flour, starter) {
        case (true, true):   return "Tippe auf ein Mehl, um es zu ersetzen, oder auf das Anstellgut, um seine TA anzupassen."
        case (true, false):  return "Tippe auf ein Mehl, um es zu ersetzen."
        case (false, true):  return "Tippe auf das Anstellgut, um seine TA anzupassen."
        case (false, false): return nil
        }
    }

    private func column(for component: ComponentColumn, at componentIndex: Int) -> some View {
        let flourWeight = showBakersPercentages ? BakersPercentage.flourWeight(of: component.ingredients) : 0

        return VStack(alignment: .leading) {
            Text(component.name)
                .font(Theme.brandFont(16))
                .padding([.bottom, .top], 5)

            VStack(alignment: .leading) {
                ForEach(Array(component.ingredients.enumerated()), id: \.offset) { ingredientIndex, ingredient in
                    let line = Text(lineText(for: ingredient, flourWeight: flourWeight))
                        .font(Theme.bodyFont(15))
                        .fixedSize(horizontal: false, vertical: true)

                    if let onFlourTap, FlourSubstitution.recognize(ingredient.name) != nil {
                        Button {
                            onFlourTap(componentIndex, ingredientIndex)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                line
                                Image(systemName: "arrow.left.arrow.right.circle")
                                    .font(.caption)
                                    .foregroundColor(Theme.accentText)
                            }
                        }
                        // Plain, so the tap belongs to the line and not to the card.
                        .buttonStyle(.plain)
                        .accessibilityHint("Mehl ersetzen")
                    } else if let onStarterTap, isAdjustableStarter(ingredient) {
                        Button {
                            onStarterTap(componentIndex, ingredientIndex)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                line
                                Image(systemName: "drop.circle")
                                    .font(.caption)
                                    .foregroundColor(Theme.accentText)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Anstellgut-TA anpassen")
                    } else {
                        line
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lineText(for ingredient: TotalIngredientData, flourWeight: Double) -> String {
        "• " + Rational.getPortion(unit: ingredient.unit,
                                   weight: ingredient.weight,
                                   num: ingredient.numerator,
                                   denom: ingredient.denominator,
                                   scale: scale)
            + ingredient.name.trimmingCharacters(in: .whitespaces)
            + BakersPercentage.suffix(for: ingredient, flourWeight: flourWeight)
    }
}

/// Baker's percentages: every ingredient of a component as a share of that
/// component's flour, which is how bakers compare and scale formulas. Flour
/// is recognised by name; a component without any shows no percentages.
enum BakersPercentage {

    /// The same flour the dough yield counts, so the two never disagree.
    static func isFlour(_ name: String) -> Bool {
        DoughComposition.isFlour(name)
    }

    /// The summed weight of the flours, independent of the scale shown —
    /// percentages do not change with the batch size.
    static func flourWeight(of ingredients: [TotalIngredientData]) -> Double {
        ingredients.filter { isFlour($0.name) && $0.weight > 0 }.map(\.weight).reduce(0, +)
    }

    /// " · 62 %" for a weighed ingredient; nothing for pieces, for a whole
    /// component used as an ingredient ("1 gesamtes Brühstück", no unit), or
    /// when the component has no flour. Non-breaking spaces keep the
    /// percentage in one piece when a narrow column wraps the line.
    static func suffix(for ingredient: TotalIngredientData, flourWeight: Double) -> String {
        guard flourWeight > 0, ingredient.weight > 0,
              !ingredient.unit.trimmingCharacters(in: .whitespaces).isEmpty
        else { return "" }
        let percent = (ingredient.weight / flourWeight * 100).rounded()
        guard percent >= 1 else { return "" }
        return " ·\u{00A0}\(Int(percent))\u{00A0}%"
    }
}
