//
//  DoughYieldView.swift
//  BackPlaner
//
//  "TA 172 · Hydration 72 %" under the recipe weight, opening the breakdown
//  by component and the assumptions behind it.
//

import SwiftUI

struct DoughYieldView: View {

    let result: DoughComposition.Result?

    @State private var showDetails = false

    var body: some View {
        if let result {
            let doughYield = Int(result.doughYield.rounded())
            let hydration  = Int(result.hydration.rounded())
            // The percent sign travels inside the value: a bare "%" at the
            // end of a format string is not something to rely on.
            let hydrationText = "\(hydration) %"

            Button {
                showDetails = true
            } label: {
                HStack(spacing: 4) {
                    Text("TA \(doughYield) · Hydration \(hydrationText)")
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                .font(Theme.bodyFont(15))
            }
            .buttonStyle(.borderless)
            .tint(Theme.accentText)
            .accessibilityLabel("Teigausbeute \(doughYield), Hydration \(hydration) Prozent")
            .accessibilityHint("Zeigt Mehl und Wasser je Komponente")
            .sheet(isPresented: $showDetails) {
                DoughCompositionSheet(result: result)
            }
        }
    }
}

/// The breakdown: totals, every component's own flour and water, the
/// starters with the TA they were split by, and what was left out.
struct DoughCompositionSheet: View {

    let result: DoughComposition.Result

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Mehl") { gramsText(result.flour) }
                    LabeledContent("Wasser") { gramsText(result.water) }
                    LabeledContent("Teigausbeute", value: yieldText(result.doughYield))
                    LabeledContent("Hydration", value: percentText(result.hydration))
                }

                Section("Komponenten") {
                    ForEach(result.components) { component in
                        LabeledContent {
                            Text(component.doughYield.map(yieldText) ?? "–")
                        } label: {
                            Text(component.name)
                            HStack(spacing: 4) {
                                gramsText(component.flour)
                                Text("Mehl")
                                Text(verbatim: "·")
                                gramsText(component.water)
                                Text("Wasser")
                            }
                            .font(.footnote)
                            .foregroundColor(Theme.subtitle)
                        }
                    }
                }

                if !result.starters.isEmpty {
                    Section("Anstellgut") {
                        ForEach(result.starters) { starter in
                            LabeledContent {
                                Text(yieldText(starter.doughYield))
                            } label: {
                                HStack(spacing: 4) {
                                    gramsText(starter.grams)
                                    Text(starter.name)
                                }
                                HStack(spacing: 4) {
                                    gramsText(starter.flour)
                                    Text("Mehl")
                                    Text(verbatim: "·")
                                    gramsText(starter.water)
                                    Text("Wasser")
                                    Text(verbatim: "·")
                                    Text(sourceText(starter.source))
                                }
                                .font(.footnote)
                                .foregroundColor(Theme.subtitle)
                            }
                        }
                    }
                }

                if !result.uncounted.isEmpty {
                    Section("Nicht gezählt") {
                        ForEach(result.uncounted) { item in
                            HStack(spacing: 4) {
                                gramsText(item.grams)
                                Text(item.name)
                            }
                        }
                    }
                }

                Section {
                    Text("Die Teigausbeute zählt Schüttflüssigkeit voll, auch Milch, Bier und Wein, und teilt Anstellgut nach seiner eigenen TA in Mehl und Wasser auf. Saaten, Flocken, Fett und Eier zählen nicht. Die TA eines Anstellguts ohne Angabe im Rezept legst Du in den Einstellungen fest.")
                        .font(.footnote)
                        .foregroundColor(Theme.subtitle)
                }
            }
            .font(Theme.bodyFont(15))
            .navigationTitle("Teigausbeute und Hydration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func gramsText(_ grams: Double) -> Text {
        Text("\(Int(grams.rounded()), format: .number) g")
    }

    private func yieldText(_ doughYield: Double) -> String {
        "TA \(Int(doughYield.rounded()))"
    }

    private func percentText(_ percent: Double) -> String {
        "\(Int(percent.rounded())) %"
    }

    private func sourceText(_ source: DoughComposition.YieldSource) -> LocalizedStringKey {
        switch source {
        case .name:       return "TA aus dem Zutatennamen"
        case .setting:    return "TA aus den Einstellungen"
        case .definition: return "TA nach Definition"
        }
    }
}
