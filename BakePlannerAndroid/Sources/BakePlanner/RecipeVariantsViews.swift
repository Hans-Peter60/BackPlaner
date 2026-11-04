import BakePlannerCore
import Foundation
import SwiftUI

/// Recipe variants on the recipe page, as the iPhone has them: the line that
/// says which recipe a variant came from and what it changes, the
/// comparison with its origin, the origin's list of its variants with how
/// each one baked, and the sheet that makes a new variant by hand.

// MARK: - On a variant: where it came from

struct VariantOriginRow: View {
    let recipe: StoredRecipe
    let origin: StoredRecipe
    /// Opens the origin's page.
    let onOpen: (String) -> Void
    @State var showsComparison = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                onOpen(origin.id)
            } label: {
                Text("Variante von „\(origin.content.name)“")
                    .font(AppFont.headline)
                    .foregroundStyle(Palette.accentText(colorScheme))
            }
            if let note = recipe.variantNote, !note.isEmpty {
                Text(verbatim: note)
                    .font(AppFont.body)
            }
            // Plain text: Skip draws no "arrow.left.arrow.right", only a
            // warning triangle in its place.
            Button("Vergleichen") {
                showsComparison = true
            }
            .font(AppFont.subheadline)
            .foregroundStyle(Palette.accentText(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Palette.cardTitle(colorScheme))
        .cardStyle()
        .appSheet(isPresented: $showsComparison) {
            NavigationStack {
                RecipeComparisonSheet(origin: origin, variant: recipe)
            }
        }
    }
}

// MARK: - The comparison

struct RecipeComparisonSheet: View {
    let origin: StoredRecipe
    let variant: StoredRecipe
    @Environment(\.dismiss) var dismiss

    var body: some View {
        let lines = RecipeDifference.between(origin.content, variant.content).lines()
        Form {
            if let note = variant.variantNote, !note.isEmpty {
                Section {
                    Text(verbatim: note)
                } header: {
                    Text("Was ist anders")
                }
            }
            Section {
                if lines.isEmpty {
                    Text("Kein Unterschied zum Ursprungsrezept.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line)
                    }
                }
            } header: {
                Text("Unterschiede zu „\(origin.content.name)“")
            }
        }
        .navigationTitle(Text(verbatim: variant.content.name))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen") { dismiss() }
            }
        }
    }
}

// MARK: - On the origin: its variants

struct VariantsSection: View {
    let model: AppModel
    let recipe: StoredRecipe
    /// Opens a variant's page.
    let onOpen: (String) -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let variants = model.variants(of: recipe.id)
        if !variants.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Varianten")
                    .font(AppFont.headline)
                ForEach(variants, id: \.id) { variant in
                    Button {
                        onOpen(variant.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: variant.content.name)
                                .font(AppFont.subheadline)
                            let change = Self.changeText(of: variant, origin: recipe)
                            if !change.isEmpty {
                                Text(verbatim: change)
                                    .font(AppFont.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(verbatim: Self.bakesText(of: variant, in: model))
                                .font(AppFont.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Palette.cardTitle(colorScheme))
            .cardStyle()
        }
    }

    /// The baker's note, or what the app finds different when there is none.
    static func changeText(of variant: StoredRecipe, origin: StoredRecipe) -> String {
        if let note = variant.variantNote, !note.isEmpty { return note }
        return RecipeDifference.between(origin.content, variant.content).summary()
    }

    /// "3-mal gebacken · zuletzt 12.10.2026: ★★★★ · offen", or that the
    /// variant has not been baked yet. Only bakes that already happened.
    static func bakesText(of variant: StoredRecipe, in model: AppModel, now: Date = Date()) -> String {
        let completed = model.bakeHistory.filter { $0.recipeID == variant.id && $0.date <= now }
        let last = completed.max(by: { $0.date < $1.date })
        return RecipeVariantText.bakes(completedCount: completed.count,
                                       lastDateText: last.map { DateFormat().calculateDate(dT: $0.date) } ?? "",
                                       lastFactsLine: last?.facts.summaryLine() ?? "")
    }
}

// MARK: - A new variant by hand

struct NewVariantSheet: View {
    let model: AppModel
    let origin: StoredRecipe
    /// Told about the new variant, which the page then opens.
    let onCreated: (StoredRecipe) -> Void
    @State var note = ""
    @State var saveFailed = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section {
                TextField("z. B. mehr Salz, längere Stockgare", text: $note, axis: .vertical)
            } header: {
                Text("Was ist anders? (optional)")
            } footer: {
                Text("Die Variante wird als Kopie von „\(origin.content.name)“ angelegt und bleibt mit dem Rezept verbunden: Ihre Backvorgänge erscheinen dort unter „Varianten“. Die Änderung selbst machst Du danach mit „Bearbeiten“.")
            }
            if saveFailed {
                Text("Speichern fehlgeschlagen")
                    .foregroundStyle(Color.red)
            }
        }
        .navigationTitle("Neue Variante")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Anlegen") {
                    if let variant = model.addVariant(of: origin, note: note) {
                        onCreated(variant)
                        dismiss()
                    } else {
                        saveFailed = true
                    }
                }
            }
        }
    }
}
