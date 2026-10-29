//
//  FlourSubstitutionView.swift
//  BackPlaner
//
//  Two ways into the flour substitution (see FlourSubstitution): a
//  free-standing calculator from the main menu — amount, flour on hand,
//  flour wanted — and a sheet opened from a flour line of a recipe, which
//  also recalculates the dough yield and can write the swap into a copy
//  of the recipe.
//

import SwiftUI
import CoreData

// MARK: - Shared pieces

/// Every catalogue flour, grouped by grain, as a navigation-link picker.
private struct FlourPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: FlourSubstitution.Flour

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(FlourSubstitution.Grain.allCases) { grain in
                Section(grain.title) {
                    ForEach(FlourSubstitution.flours(of: grain)) { flour in
                        Text(flour.title).tag(flour)
                    }
                }
            }
        }
        .pickerStyle(.navigationLink)
    }
}

private struct FlourHintsSection: View {
    let hints: [FlourSubstitution.Hint]

    var body: some View {
        if !hints.isEmpty {
            Section("Worauf achten") {
                ForEach(hints) { hint in
                    Label {
                        Text(hint.text)
                            .font(Theme.bodyFont(15))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lightbulb")
                            .foregroundColor(Theme.accentText)
                    }
                }
            }
        }
    }
}

private enum FlourText {
    /// "+20 g", "−20 g", "±0 g" — a true minus sign, not a hyphen.
    static func delta(_ grams: Double) -> String {
        let whole = Int(grams.rounded())
        if whole == 0 { return "±0 g" }
        return whole > 0 ? "+\(whole) g" : "−\(-whole) g"
    }

    /// "+4 %" — what a flour binds beyond wheat 550. A non-breaking space
    /// keeps the sign from wrapping away from its number.
    static func extraWater(_ share: Double) -> String {
        let percent = Int((share * 100).rounded())
        if percent == 0 { return "±0\u{00A0}%" }
        return percent > 0 ? "+\(percent)\u{00A0}%" : "−\(-percent)\u{00A0}%"
    }

    static let rulesOfThumb: LocalizedStringKey = "Richtwerte: Mehle werden 1:1 nach Gewicht getauscht, nur das Wasser ändert sich. Wie viel ein Mehl bindet, schwankt je nach Mühle und Ernte – der Teig hat das letzte Wort."
}

// MARK: - Calculator (main menu)

struct FlourSubstitutionCalculatorView: View {

    @State private var gramsText = "500"
    @State private var source = FlourSubstitution.wheat550
    @State private var target = FlourSubstitution.flours(of: .spelt).first { $0.milling == .type(630) }!

    @FocusState private var gramsFocused: Bool

    private var grams: Double {
        Double(gramsText.filter(\.isNumber)) ?? 0
    }

    private var delta: Double {
        FlourSubstitution.waterDelta(grams: grams, from: source, to: target)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Text("Wasser anpassen")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.subtitle)

                    Text(verbatim: FlourText.delta(delta))
                        .font(Theme.brandFont(40))
                        .foregroundColor(Theme.cardTitle)

                    // Names and percentages only; nothing in it to translate.
                    Text(verbatim: "\(source.title) \(FlourText.extraWater(source.extraWater)) → \(target.title) \(FlourText.extraWater(target.extraWater))")
                        .font(.footnote)
                        .foregroundColor(Theme.subtitle)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.clear)

            Section("Mehl") {
                HStack {
                    Text("Menge")
                    Spacer()
                    TextField("", text: $gramsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 60, maxWidth: 90)
                        .focused($gramsFocused)
                        .accessibilityLabel("Menge")
                    Text(verbatim: "g")
                        .foregroundColor(Theme.subtitle)
                    if gramsFocused {
                        Button("Fertig") { gramsFocused = false }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                FlourPicker(title: "Im Rezept", selection: $source)
                FlourPicker(title: "Ersetzen durch", selection: $target)
            }

            FlourHintsSection(hints: FlourSubstitution.hints(from: source, to: target, ryeShareAfter: nil))

            Section {
                EmptyView()
            } footer: {
                Text(FlourText.rulesOfThumb)
            }
        }
        .clearScrollBackground()
        .warmBackground()
        .navigationTitle("Mehl ersetzen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sheet from a recipe line

/// What a tapped flour line hands to the sheet: the recipe as plain data and
/// the position of the line within it.
struct FlourSubstitutionRequest: Identifiable {
    let id = UUID()
    let recipe: RecipeExportData
    let componentIndex: Int
    let ingredientIndex: Int
    /// The serving scale the recipe screen is showing (1.0 is the recipe as
    /// stored). The sheet shows its grams at this scale, so they match the
    /// line that was tapped; the copy it writes keeps the base amounts, as
    /// every recipe does.
    var scale: Double = 1
    /// The recipe to change in place: set when the recipe on screen is
    /// itself an adjusted copy, so a second adjustment does not stack a copy
    /// on a copy. `nil` writes a new copy.
    var updateTarget: NSManagedObjectID? = nil
    /// Told about the new copy, so the screen can open it.
    var onCopyCreated: ((NSManagedObjectID) -> Void)? = nil
}

struct FlourSubstitutionSheet: View {

    let request: FlourSubstitutionRequest

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var target: FlourSubstitution.Flour
    @State private var saveFailed = false

    private let source: FlourSubstitution.Flour?
    private let ingredient: RecipeExportIngredient
    private let componentName: String

    init(request: FlourSubstitutionRequest) {
        self.request = request
        let component = request.recipe.components[request.componentIndex]
        componentName = component.name
        ingredient = component.ingredients[request.ingredientIndex]
        source = FlourSubstitution.recognize(ingredient.name)

        // Start on the most common swap: wheat for anything else, spelt for wheat.
        let initial: FlourSubstitution.Flour
        if let source, source == FlourSubstitution.wheat550 {
            initial = FlourSubstitution.flours(of: .spelt).first { $0.milling == .type(630) }!
        } else {
            initial = FlourSubstitution.wheat550
        }
        _target = State(initialValue: initial)
    }

    private var applied: FlourSubstitution.Applied? {
        FlourSubstitution.apply(to: request.recipe,
                                componentIndex: request.componentIndex,
                                ingredientIndex: request.ingredientIndex,
                                target: target)
    }

    private var yieldBefore: DoughComposition.Result? {
        DoughComposition.compute(DoughComposition.components(of: request.recipe))
    }

    private var yieldAfter: DoughComposition.Result? {
        applied.flatMap { DoughComposition.compute(DoughComposition.components(of: $0.recipe)) }
    }

    private var grams: Double {
        ingredient.normWeight > 0 ? ingredient.normWeight : ingredient.weight
    }

    /// "2,0" — the factor named in the footer when it is not 1.
    private var scaleText: String {
        request.scale.formatted(.number.precision(.fractionLength(1...2)).locale(AppSettings.locale))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Im Rezept") {
                    // Grams as the recipe screen shows them, at its serving scale.
                    LabeledContent(componentName) {
                        Text(verbatim: "\(Int((grams * request.scale).rounded())) g \(ingredient.name)")
                            .multilineTextAlignment(.trailing)
                    }
                    if let source {
                        LabeledContent("Erkannt als", value: source.title)
                    }
                }

                Section {
                    FlourPicker(title: "Ersetzen durch", selection: $target)
                }

                if let applied {
                    Section {
                        // Names the line that moves — "Milch" in a component
                        // that has no water of its own. Grams at the serving
                        // scale, like the line that was tapped.
                        if let liquid = applied.adjustedLiquidName {
                            LabeledContent(liquid, value: FlourText.delta(applied.waterDelta * request.scale))
                        } else {
                            LabeledContent("Wasser", value: FlourText.delta(applied.waterDelta * request.scale))
                        }

                        if let before = yieldBefore, let after = yieldAfter {
                            LabeledContent("Teigausbeute") {
                                Text(verbatim: "TA \(Int(before.doughYield.rounded())) → \(Int(after.doughYield.rounded()))")
                            }
                            LabeledContent("Hydration") {
                                Text(verbatim: "\(Int(before.hydration.rounded())) % → \(Int(after.hydration.rounded())) %")
                            }
                        }

                        if applied.waterDelta != 0, !applied.waterAdjusted {
                            Label {
                                Text("In dieser Komponente gibt es keine Flüssigkeit (Wasser, Milch …) – die Flüssigkeit bitte von Hand anpassen.")
                                    .font(.footnote)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .foregroundColor(Theme.warning)
                        }
                    } header: {
                        Text("Ergebnis")
                    } footer: {
                        // The grams follow the factor chosen under Details, so
                        // they match the line that was tapped.
                        if request.scale != 1 {
                            // Named as factor and as dough weight, since the
                            // factor may have come from a typed dough weight.
                            Text("Mengen für Faktor ×\(scaleText), also \(Int((request.recipe.totalWeight * request.scale).rounded()), format: .number) g Teig. Die Kopie wird mit den Grundmengen des Rezepts angelegt und zeigt denselben Faktor beim Öffnen.")
                        }
                    }

                    FlourHintsSection(hints: FlourSubstitution.hints(
                        from: applied.source,
                        to: applied.target,
                        ryeShareAfter: FlourSubstitution.ryeShare(in: applied.recipe)))

                    Section {
                        if request.updateTarget != nil {
                            IconActionButton(systemImage: "checkmark.circle", style: .primary, accessibilityLabel: "Änderung übernehmen", title: "Änderung übernehmen", controlSize: .regular) {
                                applyInPlace(applied)
                            }
                        } else {
                            IconActionButton(systemImage: "doc.on.doc", style: .primary, accessibilityLabel: "Kopie mit Ersatz anlegen", title: "Kopie mit Ersatz anlegen", controlSize: .regular) {
                                createCopy(applied)
                            }
                        }
                    } footer: {
                        if request.updateTarget != nil {
                            Text("Dieses Rezept ist bereits eine angepasste Kopie. Die Änderung wird direkt übernommen, es entsteht keine weitere Kopie.")
                        } else {
                            Text("Legt unter „Eigene Rezepte“ ein neues Rezept mit dem getauschten Mehl und dem angepassten Wasser an, mit dem heutigen Datum im Namen, und öffnet es. Das Original bleibt unverändert.")
                        }
                    }
                } else {
                    Section {
                        Text("Diese Zutat wird nicht als Mehl erkannt.")
                            .foregroundColor(Theme.subtitle)
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text(FlourText.rulesOfThumb)
                }
            }
            .clearScrollBackground()
            .warmBackground()
            .navigationTitle("Mehl ersetzen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .alert("Speichern fehlgeschlagen", isPresented: $saveFailed) {
                Button("OK", role: .cancel) { }
            }
        }
    }

    /// Writes the copy, marks it as an adjusted one and hands it to the
    /// screen, which opens it once this sheet is gone.
    private func createCopy(_ applied: FlourSubstitution.Applied) {
        let copy = applied.recipe.makeRecipe(in: viewContext)
        copy.adjustedOn = Date()
        do {
            try viewContext.save()
            request.onCopyCreated?(copy.objectID)
            dismiss()
        } catch {
            viewContext.rollback()
            saveFailed = true
        }
    }

    /// Changes the adjusted copy on screen instead of copying it again.
    private func applyInPlace(_ applied: FlourSubstitution.Applied) {
        guard let target = request.updateTarget,
              let recipe = try? viewContext.existingObject(with: target) as? Recipe
        else {
            saveFailed = true
            return
        }
        applied.recipe.update(recipe, in: viewContext)
        recipe.adjustedOn = Date()
        do {
            try viewContext.save()
            dismiss()
        } catch {
            viewContext.rollback()
            saveFailed = true
        }
    }
}

#Preview {
    NavigationStack {
        FlourSubstitutionCalculatorView()
    }
}

// MARK: - Hint texts

// The wording lives with the view that shows it, so the logic itself needs
// no SwiftUI.
extension FlourSubstitution.Hint {
    var text: LocalizedStringKey {
        switch self {
        case .speltHandling:
            return "Dinkelteig kürzer und schonender kneten, lieber dehnen und falten – er neigt zum Überkneten und wird sonst trocken."
        case .speltSoaker:
            return "Dinkel bindet Wasser langsamer: Ein Quell- oder Kochstück aus einem Teil des Mehls hält die Krume saftig."
        case .ryeAcidify:
            // The share is formatted in code: "20 %" in German, "20%" in English.
            return "Roggen hat kein Klebergerüst: Ab etwa \(FlourSubstitution.ryeAcidifyShare, format: .percent) Roggenanteil den Teig mit Sauerteig versäuern, sonst wird die Krume klitschig."
        case .ryeMixOnly:
            return "Bei über der Hälfte Roggen den Teig nur mischen statt kneten, mit nassen Händen formen und kräftig versäuern."
        case .emmer:
            return "Emmer hat einen weichen Kleber: kurz kneten, kurze Gare, am sichersten in der Kastenform backen."
        case .einkorn:
            return "Einkorn bindet wenig Wasser und ist klebrig: deutlich weniger Wasser, kaum kneten, Kastenform statt freigeschoben."
        case .durumAutolyse:
            return "Hartweizen quillt langsam: 30–60 Minuten Autolyse einplanen; der Teig wird fester und gelblich."
        case .wholeGrainSoak:
            return "Vollkorn braucht Zeit zum Quellen: Autolyse oder ein Brüh-/Quellstück einplanen; die Krume wird dichter."
        case .wheatKnead:
            return "Weizen hat mehr Kleber als Dinkel, Emmer oder Einkorn: etwas länger kneten, bis der Teig ein Fenster zieht."
        case .addWaterGradually:
            return "Das zusätzliche Wasser nach und nach einarbeiten und nach Teiggefühl korrigieren – Mehle schwanken je nach Mühle und Ernte."
        }
    }
}
