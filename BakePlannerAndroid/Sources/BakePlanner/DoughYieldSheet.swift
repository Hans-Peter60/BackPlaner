import BakePlannerCore
import SwiftUI

/// "TA 172 · Hydration 72 %" under the recipe weight, as on the iPhone
/// (DoughYieldView): a tap opens the breakdown by component and the
/// assumptions behind it. Nothing when the recipe names no flour.
struct DoughYieldRow: View {
    let content: RecipeExportData
    @State var showsDetails = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if let result = DoughComposition.compute(DoughComposition.components(of: content)), result.flour > 0 {
            let doughYield = Int(result.doughYield.rounded())
            let hydration = result.hydration.formatted(.number.precision(.fractionLength(0))) + " %"
            Button {
                showsDetails = true
            } label: {
                HStack(spacing: 4) {
                    Text("TA \(doughYield) · Hydration \(hydration)")
                    Image(systemName: "info.circle")
                        .font(AppFont.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accent(colorScheme))
            .appSheet(isPresented: $showsDetails) {
                NavigationStack {
                    DoughYieldSheet(result: result)
                }
            }
        }
    }
}

/// The breakdown: totals, every component's own flour and water, the
/// starters with the TA they were split by, and what was left out — the
/// iPhone's DoughCompositionSheet.
struct DoughYieldSheet: View {
    let result: DoughComposition.Result
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            Section {
                LabeledContent("Mehl", value: gramsText(result.flour))
                LabeledContent("Wasser", value: gramsText(result.water))
                LabeledContent("Teigausbeute", value: yieldText(result.doughYield))
                LabeledContent("Hydration", value: percentText(result.hydration))
                // The flour that ferments before the main dough is mixed.
                if result.prefermentedFlour > 0 {
                    LabeledContent("Vorfermentiertes Mehl",
                                   value: gramsText(result.prefermentedFlour) + " · " + percentText(result.prefermentedShare))
                }
            }

            // Salt and yeast far from the usual baker's percentages, as on
            // the iPhone; the texts come from the package.
            let hints = DoughPlausibility.hints(for: result)
            if !hints.isEmpty {
                Section {
                    ForEach(keyedRows(hints, prefix: "hint")) { row in
                        Text(verbatim: row.value.text)
                    }
                } header: {
                    Text("Hinweise")
                }
            }

            Section {
                ForEach(keyedRows(result.components, prefix: "component")) { row in
                    let component = row.value
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(verbatim: component.name)
                            Spacer()
                            Text(verbatim: component.doughYield.map(yieldText) ?? "–")
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Text(verbatim: gramsText(component.flour))
                            Text("Mehl")
                            Text(verbatim: "·")
                            Text(verbatim: gramsText(component.water))
                            Text("Wasser")
                        }
                        .font(AppFont.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Komponenten")
            }

            if !result.starters.isEmpty {
                Section {
                    ForEach(keyedRows(result.starters, prefix: "starter")) { row in
                        let starter = row.value
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(verbatim: gramsText(starter.grams) + " " + starter.name)
                                Spacer()
                                Text(verbatim: yieldText(starter.doughYield))
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                Text(verbatim: gramsText(starter.flour))
                                Text("Mehl")
                                Text(verbatim: "·")
                                Text(verbatim: gramsText(starter.water))
                                Text("Wasser")
                                Text(verbatim: "·")
                                sourceText(starter.source)
                            }
                            .font(AppFont.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Anstellgut")
                }
            }

            if !result.uncounted.isEmpty {
                Section {
                    ForEach(keyedRows(result.uncounted, prefix: "uncounted")) { row in
                        let item = row.value
                        Text(verbatim: gramsText(item.grams) + " " + item.name)
                    }
                } header: {
                    Text("Nicht gezählt")
                }
            }

            Section {
                Text("Die Teigausbeute zählt Schüttflüssigkeit voll, auch Milch, Bier und Wein, und teilt Anstellgut nach seiner eigenen TA in Mehl und Wasser auf. Saaten, Flocken, Fett und Eier zählen nicht. Die TA eines Anstellguts ohne Angabe im Rezept legst Du in den Einstellungen fest.")
                    .font(AppFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Teigausbeute und Hydration")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") {
                    dismiss()
                }
            }
        }
    }

    // The lines are put together from several Texts, as on the iPhone: the
    // words come out of the catalog, the numbers stay verbatim.
    private func gramsText(_ grams: Double) -> String {
        "\(Int(grams.rounded())) g"
    }

    private func yieldText(_ doughYield: Double) -> String {
        "TA \(Int(doughYield.rounded()))"
    }

    private func percentText(_ percent: Double) -> String {
        "\(Int(percent.rounded())) %"
    }

    private func sourceText(_ source: DoughComposition.YieldSource) -> Text {
        switch source {
        case .name: return Text("TA aus dem Zutatennamen")
        case .setting: return Text("TA aus den Einstellungen")
        case .definition: return Text("TA nach Definition")
        }
    }
}

/// A list row with a key unique across the whole list. The shares of the
/// composition number their ids from 0 in every group, and Skip's List
/// keys its rows by id: two rows with id 0 crashed it ("Key was already
/// used").
struct Keyed<Value>: Identifiable {
    let id: String
    let value: Value
}

func keyedRows<Item: Identifiable>(_ items: [Item], prefix: String) -> [Keyed<Item>] {
    items.map { Keyed<Item>(id: prefix + "-" + String(describing: $0.id), value: $0) }
}
