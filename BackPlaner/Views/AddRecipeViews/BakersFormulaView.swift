//
//  BakersFormulaView.swift
//  BackPlaner
//
//  "Rezept nach Bäckerprozent anlegen": the formula the baker's way — every
//  ingredient as a share of the flour, the flours together 100 % — plus the
//  flour weight or the dough weight wanted. "Weiter" turns it into a recipe
//  in grams and opens the editor, where the steps are added. The arithmetic
//  is BakersFormula in the package.
//

import BakePlannerCore
import SwiftUI

struct BakersFormulaView: View {

    /// What the person gives: the flour, or the dough they want.
    private enum Basis: Hashable {
        case flour, dough
    }

    @Environment(\.locale) private var locale

    @State private var name = ""
    @State private var formula = BakersFormula.template()
    @State private var basis = Basis.flour
    @State private var amount: Double = 500
    @State private var newComponentName = ""
    @State private var recipe: RecipeFB?
    @State private var showRecipeReview = false

    private var totalFlour: Double {
        basis == .flour ? amount : formula.totalFlour(forDoughWeight: amount)
    }

    private var canContinue: Bool {
        formula.isComplete && totalFlour > 0
    }

    var body: some View {
        Form {
            Section {
                TextField("Rezeptname", text: $name)
            }

            Section {
                Picker("Vorgabe", selection: $basis) {
                    Text("Mehl gesamt").tag(Basis.flour)
                    Text("Teiggewicht").tag(Basis.dough)
                }
                .pickerStyle(.segmented)
                HStack {
                    NumberField(basis == .flour ? "Mehl gesamt" : "Teiggewicht", value: $amount)
                        .keyboardType(.decimalPad)
                    Text(verbatim: "g")
                        .foregroundColor(Theme.subtitle)
                }
                LabeledContent(basis == .flour ? "Teiggewicht" : "Mehl gesamt",
                               value: gramsText(basis == .flour ? formula.doughWeight(forTotalFlour: amount) : totalFlour))
            } header: {
                Text("Menge")
            } footer: {
                Text("Alle Prozente beziehen sich auf das gesamte Mehl des Rezepts – alle Mehle zusammen sind 100 Prozent. Gib die Mehlmenge oder das gewünschte Teiggewicht vor, die Gramm rechnet die App.")
            }

            ForEach($formula.components) { $component in
                Section {
                    LabeledContent("Komponente") {
                        TextField("Name der Komponente", text: $component.name)
                            .multilineTextAlignment(.trailing)
                    }
                    ForEach($component.lines) { $line in
                        lineRow($line)
                    }
                    .onDelete { offsets in
                        component.lines.remove(atOffsets: offsets)
                    }
                    Button {
                        component.lines.append(BakersFormula.Line(name: "", percent: 0))
                    } label: {
                        Label("Zutat hinzufügen", systemImage: "plus.circle")
                    }
                    if formula.components.count > 1 {
                        Button(role: .destructive) {
                            formula.components.removeAll { $0.id == component.id }
                        } label: {
                            Label("Komponente entfernen", systemImage: "minus.circle")
                        }
                    }
                } header: {
                    Text(verbatim: component.name.isEmpty ? " " : component.name)
                }
            }

            Section {
                HStack {
                    TextField("Neue Komponente", text: $newComponentName)
                    Button("Hinzufügen") {
                        let trimmed = newComponentName.trimmingCharacters(in: .whitespaces)
                        formula.components.append(BakersFormula.Component(
                            name: trimmed, lines: [BakersFormula.Line(name: "", percent: 0)]))
                        newComponentName = ""
                    }
                    .disabled(newComponentName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                // What still keeps the formula from becoming a recipe.
                if !formula.isComplete {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(formula.issues.enumerated()), id: \.offset) { _, issue in
                            Label(issueText(issue), systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.warning)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .warmBackground()
        .navigationTitle("Nach Bäckerprozent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Weiter") {
                    recipe = formula.makeRecipe(name: name, totalFlour: totalFlour)
                    showRecipeReview = true
                }
                .disabled(!canContinue)
                .accessibilityIdentifier("formula.continue")
            }
        }
        .navigationDestination(isPresented: $showRecipeReview) {
            if let recipe {
                AddNewRecipeDataView(recipe: recipe)
            }
        }
    }

    /// Name, "Mehl" where the line counts as flour, the share and the grams.
    private func lineRow(_ line: Binding<BakersFormula.Line>) -> some View {
        HStack(spacing: 8) {
            TextField("Zutat", text: line.name)
            if line.wrappedValue.isFlour {
                Text("Mehl")
                    .font(Theme.bodyFont(11))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accentTop.opacity(0.18)))
                    .foregroundColor(Theme.accentText)
                    .accessibilityLabel("Zählt als Mehl")
            }
            // No placeholder: "Prozent" would not fit the narrow field, and
            // the "%" beside it says what the number is.
            NumberField(value: line.percent)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .accessibilityLabel("Prozent")
            Text(verbatim: "%")
                .foregroundColor(Theme.subtitle)
            Text(gramsText(formula.grams(of: line.wrappedValue, totalFlour: totalFlour)))
                .font(Theme.brandFont(14))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
        }
    }

    private func gramsText(_ grams: Double) -> String {
        let number = grams.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return "\(number) g"
    }

    private func issueText(_ issue: BakersFormula.Issue) -> String {
        switch issue {
        case .noFlour:
            return String(localized: "Keine Zutat wird als Mehl erkannt – nenne das Mehl beim Namen, etwa „Weizenmehl 550“.")
        case .flourNot100(let percent):
            let shown = percent.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
            return String(localized: "Die Mehle ergeben \(shown) Prozent statt 100.")
        case .nonPositive(let name):
            return String(localized: "„\(name)“ hat noch keinen Anteil.")
        case .noLines:
            return String(localized: "Noch keine Zutaten.")
        }
    }
}

#Preview {
    NavigationStack {
        BakersFormulaView()
    }
}
