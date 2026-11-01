import BakePlannerCore
import Foundation
import SwiftUI

/// What a tapped ingredient line hands to a sheet: the recipe as stored and
/// the position of the line within it. The grams are shown at the scale the
/// recipe screen uses, so they match the line that was tapped; a copy keeps
/// the base amounts, as every recipe does.
struct IngredientLineRequest {
    let recipe: StoredRecipe
    let componentIndex: Int
    let ingredientIndex: Int
    let scale: Double
}

/// Writes an adjusted recipe the way the iPhone does: a new copy marked as
/// adjusted, or — when the recipe on screen is itself such a copy — the
/// change into that copy, so a second adjustment does not stack copies.
/// Hands back the recipe to show afterwards, nil when saving failed.
@MainActor
private func keepAdjusted(_ content: RecipeExportData, of recipe: StoredRecipe, in model: AppModel) -> StoredRecipe? {
    if recipe.adjustedOn != nil {
        var changed = recipe
        changed.content = content
        changed.adjustedOn = Date()
        return model.save(changed) ? model.recipe(id: recipe.id) : nil
    }
    return model.addAdjustedCopy(content)
}

/// Common pieces of both sheets: dough yield before and after, the warning
/// when the component has no liquid to move, and the footer about the scale.
struct YieldChangeRows: View {
    let before: DoughComposition.Result?
    let after: DoughComposition.Result?

    var body: some View {
        if let before, let after {
            HStack {
                Text("Teigausbeute")
                Spacer()
                Text(verbatim: "TA \(Int(before.doughYield.rounded())) → \(Int(after.doughYield.rounded()))")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Hydration")
                Spacer()
                Text(verbatim: "\(Int(before.hydration.rounded())) % → \(Int(after.hydration.rounded())) %")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ScaleFooter: View {
    let recipe: RecipeExportData
    let scale: Double

    var body: some View {
        if scale != 1 {
            let factor = scale.formatted(.number.precision(.fractionLength(1...2)))
            let grams = String(Int((recipe.totalWeight * scale).rounded()))
            Text("Mengen für Faktor ×\(factor), also \(grams) g Teig. Die Kopie wird mit den Grundmengen des Rezepts angelegt und zeigt denselben Faktor beim Öffnen.")
        }
    }
}

// MARK: - Flour

/// Swaps the flour of a tapped line for another and moves the component's
/// liquid by what the new flour binds; written into a copy of the recipe,
/// or into the copy on screen (FlourSubstitution, as on the iPhone).
struct FlourSubstitutionSheet: View {
    let model: AppModel
    let request: IngredientLineRequest
    /// Told which recipe to show once the sheet is gone.
    let onKept: (StoredRecipe) -> Void
    @State var targetID: String
    @State var saveFailed = false
    @Environment(\.dismiss) var dismiss

    init(model: AppModel, request: IngredientLineRequest, onKept: @escaping (StoredRecipe) -> Void) {
        self.model = model
        self.request = request
        self.onKept = onKept
        // Start on the most common swap: wheat for anything else, spelt for wheat.
        let ingredient = request.recipe.content.components[request.componentIndex].ingredients[request.ingredientIndex]
        let source = FlourSubstitution.recognize(ingredient.name)
        let initial: FlourSubstitution.Flour
        if let source, source == FlourSubstitution.wheat550,
           let spelt = FlourSubstitution.flours(of: .spelt).first(where: { $0.milling == .type(630) }) {
            initial = spelt
        } else {
            initial = FlourSubstitution.wheat550
        }
        _targetID = State(initialValue: initial.id)
    }

    private var content: RecipeExportData { request.recipe.content }
    private var component: RecipeExportComponent { content.components[request.componentIndex] }
    private var ingredient: RecipeExportIngredient { component.ingredients[request.ingredientIndex] }
    private var source: FlourSubstitution.Flour? { FlourSubstitution.recognize(ingredient.name) }
    private var target: FlourSubstitution.Flour {
        FlourSubstitution.catalog.first { $0.id == targetID } ?? FlourSubstitution.wheat550
    }
    private var grams: Double { ingredient.normWeight > 0 ? ingredient.normWeight : ingredient.weight }

    private var applied: FlourSubstitution.Applied? {
        FlourSubstitution.apply(to: content, componentIndex: request.componentIndex,
                                ingredientIndex: request.ingredientIndex, target: target)
    }

    var body: some View {
        let applied = self.applied
        Form {
            Section {
                HStack {
                    Text(verbatim: component.name)
                    Spacer()
                    Text(verbatim: "\(Int((grams * request.scale).rounded())) g \(ingredient.name)")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                if let source {
                    HStack {
                        Text("Erkannt als")
                        Spacer()
                        Text(verbatim: source.title)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Im Rezept")
            }

            Section {
                FlourChoice(title: "Ersetzen durch", flourID: $targetID)
            }

            if let applied {
                Section {
                    HStack {
                        if let liquid = applied.adjustedLiquidName {
                            Text(verbatim: liquid)
                        } else {
                            Text("Wasser")
                        }
                        Spacer()
                        Text(verbatim: gramsDeltaText(applied.waterDelta * request.scale))
                            .foregroundStyle(.secondary)
                    }
                    YieldChangeRows(before: DoughComposition.compute(DoughComposition.components(of: content)),
                                    after: DoughComposition.compute(DoughComposition.components(of: applied.recipe)))
                    if applied.waterDelta != 0, !applied.waterAdjusted {
                        Label("In dieser Komponente gibt es keine Flüssigkeit (Wasser, Milch …) – die Flüssigkeit bitte von Hand anpassen.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.orange)
                    }
                } header: {
                    Text("Ergebnis")
                } footer: {
                    ScaleFooter(recipe: content, scale: request.scale)
                }

                let hints = FlourSubstitution.hints(from: applied.source, to: applied.target,
                                                    ryeShareAfter: FlourSubstitution.ryeShare(in: applied.recipe))
                if !hints.isEmpty {
                    Section {
                        ForEach(hints) { hint in
                            Label {
                                flourHintText(hint)
                            } icon: {
                                Image(systemName: "info.circle")
                            }
                        }
                    } header: {
                        Text("Worauf achten")
                    }
                }

                Section {
                    if request.recipe.adjustedOn != nil {
                        Button("Änderung übernehmen") {
                            keep(applied.recipe)
                        }
                    } else {
                        Button("Kopie mit Ersatz anlegen") {
                            keep(applied.recipe)
                        }
                    }
                } footer: {
                    if request.recipe.adjustedOn != nil {
                        Text("Dieses Rezept ist bereits eine angepasste Kopie. Die Änderung wird direkt übernommen, es entsteht keine weitere Kopie.")
                    } else {
                        Text("Legt unter „Eigene Rezepte“ ein neues Rezept mit dem getauschten Mehl und dem angepassten Wasser an, mit dem heutigen Datum im Namen, und öffnet es. Das Original bleibt unverändert.")
                    }
                }
            } else {
                Section {
                    Text("Diese Zutat wird nicht als Mehl erkannt.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Richtwerte: Mehle werden 1:1 nach Gewicht getauscht, nur das Wasser ändert sich. Wie viel ein Mehl bindet, schwankt je nach Mühle und Ernte – der Teig hat das letzte Wort.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Mehl ersetzen")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
        }
        .alert("Speichern fehlgeschlagen", isPresented: $saveFailed) {
            Button {
            } label: {
                Text(verbatim: "OK")
            }
        }
    }

    private func keep(_ content: RecipeExportData) {
        if let kept = keepAdjusted(content, of: request.recipe, in: model) {
            onKept(kept)
            dismiss()
        } else {
            saveFailed = true
        }
    }
}

// MARK: - Starter TA

/// Exchanges the starter of a tapped line for one of another TA and moves
/// the component's liquid so flour and water stay as the recipe meant them;
/// written into a copy, or into the copy on screen (StarterYieldAdjustment).
struct StarterYieldSheet: View {
    let model: AppModel
    let request: IngredientLineRequest
    let onKept: (StoredRecipe) -> Void
    @State var targetYield: Int
    @State var saveFailed = false
    @Environment(\.dismiss) var dismiss

    init(model: AppModel, request: IngredientLineRequest, onKept: @escaping (StoredRecipe) -> Void) {
        self.model = model
        self.request = request
        self.onKept = onKept
        let content = request.recipe.content
        let ingredient = content.components[request.componentIndex].ingredients[request.ingredientIndex]
        let source = StarterYieldAdjustment.recognize(ingredient, componentNames: content.components.map(\.name))
        // Start on the starter one keeps, as set in the settings.
        _targetYield = State(initialValue: source?.kind == .lievitoMadre
                             ? AppSettings.storedLievitoMadreDoughYield
                             : AppSettings.storedStarterDoughYield)
    }

    private var content: RecipeExportData { request.recipe.content }
    private var component: RecipeExportComponent { content.components[request.componentIndex] }
    private var ingredient: RecipeExportIngredient { component.ingredients[request.ingredientIndex] }
    private var source: StarterYieldAdjustment.Source? {
        StarterYieldAdjustment.recognize(ingredient, componentNames: content.components.map(\.name))
    }
    private var grams: Double { ingredient.normWeight > 0 ? ingredient.normWeight : ingredient.weight }
    private var presets: [Int] { AppSettings.storedStarterDoughYieldPresets }

    private var applied: StarterYieldAdjustment.Applied? {
        StarterYieldAdjustment.apply(to: content, componentIndex: request.componentIndex,
                                     ingredientIndex: request.ingredientIndex, targetYield: Double(targetYield))
    }

    /// Grams as the recipe screen shows them, at its scale.
    private func shown(_ baseGrams: Double) -> String {
        "\(Int((baseGrams * request.scale).rounded())) g"
    }

    var body: some View {
        let applied = self.applied
        Form {
            Section {
                HStack {
                    Text(verbatim: component.name)
                    Spacer()
                    Text(verbatim: "\(shown(grams)) \(ingredient.name)")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                if let source {
                    HStack {
                        Text("Erkannt als")
                        Spacer()
                        HStack(spacing: 0) {
                            starterKindText(source.kind)
                            Text(verbatim: ", TA \(Int(source.doughYield.rounded()))")
                        }
                        .foregroundStyle(.secondary)
                    }
                    if source.yieldSource == .setting {
                        HStack {
                            Text("TA laut")
                            Spacer()
                            Text("Einstellungen")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Im Rezept")
            }

            Section {
                Text("Vorhandenes Anstellgut")
                Picker("Vorhandenes Anstellgut", selection: $targetYield) {
                    ForEach(presets, id: \.self) { preset in
                        Text(verbatim: String(preset)).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Stepper(value: $targetYield,
                        in: AppSettings.minimumStarterDoughYield...AppSettings.maximumStarterDoughYield, step: 5) {
                    ValueLabel(title: "Genauer Wert", value: "TA \(targetYield)")
                }
            }

            if let applied {
                Section {
                    HStack {
                        starterKindText(applied.source.kind)
                        Spacer()
                        Text(verbatim: "\(shown(applied.source.grams)) → \(shown(applied.starterGrams))")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        if let liquid = applied.adjustedLiquidName {
                            Text(verbatim: liquid)
                        } else {
                            Text("Wasser")
                        }
                        Spacer()
                        Text(verbatim: gramsDeltaText(applied.waterDelta * request.scale))
                            .foregroundStyle(.secondary)
                    }
                    YieldChangeRows(before: DoughComposition.compute(DoughComposition.components(of: content)),
                                    after: DoughComposition.compute(DoughComposition.components(of: applied.recipe)))
                    if applied.waterDelta != 0, !applied.waterAdjusted {
                        Label("In dieser Komponente gibt es keine Flüssigkeit (Wasser, Milch …) – die Flüssigkeit bitte von Hand anpassen.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.orange)
                    }
                    if applied.waterShortfall > 0 {
                        Label {
                            Text("Die Komponente hat nicht genug Flüssigkeit, um \(shown(applied.waterShortfall)) wegzunehmen – bitte an anderer Stelle im Rezept ausgleichen.")
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(Color.orange)
                    }
                } header: {
                    Text("Ergebnis")
                } footer: {
                    ScaleFooter(recipe: content, scale: request.scale)
                }

                let hints = StarterYieldAdjustment.hints(from: applied.source.doughYield, to: applied.targetYield,
                                                         yieldSource: applied.source.yieldSource)
                if !hints.isEmpty {
                    Section {
                        ForEach(hints) { hint in
                            Label {
                                starterHintText(hint)
                            } icon: {
                                Image(systemName: "info.circle")
                            }
                        }
                    } header: {
                        Text("Worauf achten")
                    }
                }

                Section {
                    if request.recipe.adjustedOn != nil {
                        Button("Änderung übernehmen") {
                            keep(applied.recipe)
                        }
                    } else {
                        Button("Kopie mit Anpassung anlegen") {
                            keep(applied.recipe)
                        }
                    }
                } footer: {
                    if request.recipe.adjustedOn != nil {
                        Text("Dieses Rezept ist bereits eine angepasste Kopie. Die Änderung wird direkt übernommen, es entsteht keine weitere Kopie.")
                    } else {
                        Text("Legt unter „Eigene Rezepte“ ein neues Rezept mit dem angepassten Anstellgut und Wasser an, mit dem heutigen Datum im Namen, und öffnet es. Das Original bleibt unverändert.")
                    }
                }
            } else {
                Section {
                    Text("Diese Zutat wird nicht als Anstellgut oder Sauerteig erkannt.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Das Mehl aus dem Anstellgut bleibt gleich; nur Anstellgut und Wasser verschieben sich gegeneinander. Teigausbeute und Gesamtgewicht des Teigs ändern sich dadurch nicht.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Anstellgut-TA anpassen")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
        }
        .alert("Speichern fehlgeschlagen", isPresented: $saveFailed) {
            Button {
            } label: {
                Text(verbatim: "OK")
            }
        }
    }

    private func keep(_ content: RecipeExportData) {
        if let kept = keepAdjusted(content, of: request.recipe, in: model) {
            onKept(kept)
            dismiss()
        } else {
            saveFailed = true
        }
    }

    /// "Anstellgut" in the app's language; the Italian and French kinds
    /// keep their names, as on the iPhone.
    private func starterKindText(_ kind: DoughComposition.StarterKind) -> Text {
        switch kind {
        case .sourdough: return Text("Anstellgut")
        case .lievitoMadre: return Text(verbatim: "Lievito Madre")
        case .pateFermentee: return Text(verbatim: "Pâte fermentée")
        case .biga: return Text(verbatim: "Biga")
        case .poolish: return Text(verbatim: "Poolish")
        }
    }
}
