//
//  StarterYieldView.swift
//  BackPlaner
//
//  Two ways into the starter TA adjustment (see StarterYieldAdjustment):
//  a free-standing calculator from the main menu — amount, TA the recipe
//  wants, TA on hand — and a sheet opened from a starter line of a recipe,
//  which also shows the dough yield and can write the adjustment into a
//  copy of the recipe. The counterpart of FlourSubstitutionView.
//

import SwiftUI
import CoreData

// MARK: - Shared pieces

private enum StarterYieldText {
    static func grams(_ value: Double) -> String {
        "\(Int(value.rounded())) g"
    }

    /// "+20 g", "−20 g", "±0 g" — a true minus sign, not a hyphen.
    static func delta(_ grams: Double) -> String {
        let whole = Int(grams.rounded())
        if whole == 0 { return "±0 g" }
        return whole > 0 ? "+\(whole) g" : "−\(-whole) g"
    }

    static func yield(_ value: Double) -> String {
        "TA \(Int(value.rounded()))"
    }

    static func kindTitle(_ kind: DoughComposition.StarterKind) -> String {
        switch kind {
        case .sourdough:     return String(localized: "Anstellgut", bundle: AppSettings.localizationBundle, locale: AppSettings.locale, comment: "Sauerteig-Anstellgut")
        case .lievitoMadre:  return "Lievito Madre"
        case .pateFermentee: return "Pâte fermentée"
        case .biga:          return "Biga"
        case .poolish:       return "Poolish"
        }
    }

    static let rulesOfThumb: LocalizedStringKey = "Das Mehl aus dem Anstellgut bleibt gleich; nur Anstellgut und Wasser verschieben sich gegeneinander. Teigausbeute und Gesamtgewicht des Teigs ändern sich dadurch nicht."
}

/// The TAs the user keeps starters at as quick picks, with a stepper for
/// any other value. The quick picks come from Settings → Rezepte.
private struct StarterYieldPicker: View {
    let title: LocalizedStringKey
    @Binding var yield: Int

    private var presets: [Int] { AppSettings.storedStarterDoughYieldPresets }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            // A segmented picker hides its own label; the title stands above.
            Picker(title, selection: $yield) {
                ForEach(presets, id: \.self) { preset in
                    Text(verbatim: "\(preset)").tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Stepper(value: $yield,
                    in: AppSettings.minimumStarterDoughYield...AppSettings.maximumStarterDoughYield,
                    step: 5) {
                LabeledContent("Genauer Wert", value: "TA \(yield)")
            }
        }
    }
}

private struct StarterYieldHintsSection: View {
    let hints: [StarterYieldAdjustment.Hint]

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

// MARK: - Calculator (main menu)

struct StarterYieldCalculatorView: View {

    @State private var gramsText = "100"
    @State private var sourceYield = 150
    @State private var targetYield = AppSettings.storedStarterDoughYield

    @FocusState private var gramsFocused: Bool

    private var grams: Double {
        Double(gramsText.filter(\.isNumber)) ?? 0
    }

    private var starterAfter: Double {
        StarterYieldAdjustment.starterGrams(grams: grams, from: Double(sourceYield), to: Double(targetYield))
    }

    private var waterDelta: Double {
        StarterYieldAdjustment.waterDelta(grams: grams, from: Double(sourceYield), to: Double(targetYield))
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Text("Anstellgut einsetzen")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.subtitle)

                    Text(verbatim: StarterYieldText.grams(starterAfter))
                        .font(Theme.brandFont(40))
                        .foregroundColor(Theme.cardTitle)

                    Text("Wasser im Teig: \(StarterYieldText.delta(waterDelta))")
                        .font(Theme.bodyFont(15))

                    // Figures only; nothing in it to translate.
                    Text(verbatim: "\(StarterYieldText.grams(grams)) \(StarterYieldText.yield(Double(sourceYield))) → \(StarterYieldText.yield(Double(targetYield)))")
                        .font(.footnote)
                        .foregroundColor(Theme.subtitle)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.clear)

            Section("Im Rezept") {
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

                Stepper(value: $sourceYield,
                        in: AppSettings.minimumStarterDoughYield...AppSettings.maximumStarterDoughYield,
                        step: 5) {
                    LabeledContent("TA im Rezept", value: "TA \(sourceYield)")
                }
            }

            Section("Vorhanden") {
                StarterYieldPicker(title: "Mein Anstellgut", yield: $targetYield)
            }

            StarterYieldHintsSection(hints: StarterYieldAdjustment.hints(
                from: Double(sourceYield), to: Double(targetYield), yieldSource: .name))

            Section {
                EmptyView()
            } footer: {
                Text(StarterYieldText.rulesOfThumb)
            }
        }
        .clearScrollBackground()
        .warmBackground()
        .navigationTitle("Anstellgut-TA anpassen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sheet from a recipe line

/// What a tapped starter line hands to the sheet: the recipe as plain data
/// and the position of the line within it.
struct StarterYieldRequest: Identifiable {
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

struct StarterYieldSheet: View {

    let request: StarterYieldRequest

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var targetYield: Int
    @State private var saveFailed = false

    private let source: StarterYieldAdjustment.Source?
    private let ingredient: RecipeExportIngredient
    private let componentName: String

    init(request: StarterYieldRequest) {
        self.request = request
        let component = request.recipe.components[request.componentIndex]
        componentName = component.name
        ingredient = component.ingredients[request.ingredientIndex]
        source = StarterYieldAdjustment.recognize(ingredient, componentNames: request.recipe.components.map(\.name))

        // Start on the starter one keeps, as set under Einstellungen.
        let initial = source?.kind == .lievitoMadre
            ? AppSettings.storedLievitoMadreDoughYield
            : AppSettings.storedStarterDoughYield
        _targetYield = State(initialValue: initial)
    }

    private var applied: StarterYieldAdjustment.Applied? {
        StarterYieldAdjustment.apply(to: request.recipe,
                                     componentIndex: request.componentIndex,
                                     ingredientIndex: request.ingredientIndex,
                                     targetYield: Double(targetYield))
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

    /// Grams as the recipe screen shows them, at its serving scale.
    private func shown(_ baseGrams: Double) -> String {
        StarterYieldText.grams(baseGrams * request.scale)
    }

    private func shownDelta(_ baseGrams: Double) -> String {
        StarterYieldText.delta(baseGrams * request.scale)
    }

    /// "2,0" — the factor named in the footer when it is not 1.
    private var scaleText: String {
        request.scale.formatted(.number.precision(.fractionLength(1...2)).locale(AppSettings.locale))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Im Rezept") {
                    LabeledContent(componentName) {
                        Text(verbatim: "\(shown(grams)) \(ingredient.name)")
                            .multilineTextAlignment(.trailing)
                    }
                    if let source {
                        LabeledContent("Erkannt als") {
                            Text(verbatim: "\(StarterYieldText.kindTitle(source.kind)), \(StarterYieldText.yield(source.doughYield))")
                        }
                        if source.yieldSource == .setting {
                            LabeledContent("TA laut", value: "Einstellungen")
                        }
                    }
                }

                Section {
                    StarterYieldPicker(title: "Vorhandenes Anstellgut", yield: $targetYield)
                }

                if let applied {
                    Section {
                        LabeledContent(StarterYieldText.kindTitle(applied.source.kind)) {
                            Text(verbatim: "\(shown(applied.source.grams)) → \(shown(applied.starterGrams))")
                        }

                        // Names the line that moves — "Milch" in a component
                        // that has no water of its own.
                        if let liquid = applied.adjustedLiquidName {
                            LabeledContent(liquid, value: shownDelta(applied.waterDelta))
                        } else {
                            LabeledContent("Wasser", value: shownDelta(applied.waterDelta))
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

                        if applied.waterShortfall > 0 {
                            Label {
                                Text("Die Komponente hat nicht genug Flüssigkeit, um \(shown(applied.waterShortfall)) wegzunehmen – bitte an anderer Stelle im Rezept ausgleichen.")
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

                    StarterYieldHintsSection(hints: StarterYieldAdjustment.hints(
                        from: applied.source.doughYield,
                        to: applied.targetYield,
                        yieldSource: applied.source.yieldSource))

                    Section {
                        if request.updateTarget != nil {
                            IconActionButton(systemImage: "checkmark.circle", style: .primary, accessibilityLabel: "Änderung übernehmen", title: "Änderung übernehmen", controlSize: .regular) {
                                applyInPlace(applied)
                            }
                        } else {
                            IconActionButton(systemImage: "doc.on.doc", style: .primary, accessibilityLabel: "Kopie mit Anpassung anlegen", title: "Kopie mit Anpassung anlegen", controlSize: .regular) {
                                createCopy(applied)
                            }
                        }
                    } footer: {
                        if request.updateTarget != nil {
                            Text("Dieses Rezept ist bereits eine angepasste Kopie. Die Änderung wird direkt übernommen, es entsteht keine weitere Kopie.")
                        } else {
                            Text("Legt unter „Eigene Rezepte“ ein neues Rezept mit dem angepassten Anstellgut und Wasser an, mit dem heutigen Datum im Namen, und öffnet es. Das Original bleibt unverändert.")
                        }
                    }
                } else {
                    Section {
                        Text("Diese Zutat wird nicht als Anstellgut oder Sauerteig erkannt.")
                            .foregroundColor(Theme.subtitle)
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text(StarterYieldText.rulesOfThumb)
                }
            }
            .clearScrollBackground()
            .warmBackground()
            .navigationTitle("Anstellgut-TA anpassen")
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
    private func createCopy(_ applied: StarterYieldAdjustment.Applied) {
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
    private func applyInPlace(_ applied: StarterYieldAdjustment.Applied) {
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
        StarterYieldCalculatorView()
    }
}

// MARK: - Hint texts

// The wording lives with the view that shows it, so the logic itself needs
// no SwiftUI.
extension StarterYieldAdjustment.Hint {
    var text: LocalizedStringKey {
        switch self {
        case .softer:
            return "Weicheres Anstellgut (höhere TA) gärt schneller und säuert milder – die Reifezeit des Sauerteigs eher etwas kürzer ansetzen."
        case .firmer:
            return "Festeres Anstellgut (niedrigere TA) arbeitet langsamer und säuert kräftiger – etwas mehr Reifezeit einplanen."
        case .bigStep:
            return "Bei großen TA-Unterschieden lohnt es sich, das Anstellgut vorher mit ein bis zwei Fütterungen auf die gewünschte TA umzustellen."
        case .assumedYield:
            return "Das Rezept nennt keine TA für sein Anstellgut; angenommen ist die TA aus den Einstellungen. Steht sie im Rezept, trage sie in den Zutatennamen ein, etwa „Anstellgut TA 150“."
        }
    }
}
