//
//  RecipeVariantsViews.swift
//  BackPlaner
//
//  Recipe variants on the recipe page: the line that says which recipe a
//  variant came from and what it changes, the comparison with its origin,
//  the origin's list of its variants with how each one baked, and the
//  sheet that makes a new variant by hand. A variant is a recipe of its own
//  that knows its origin (Recipe.origin); the flour substitution and the
//  starter adjustment write theirs with a note, "Variante anlegen" lets the
//  baker write the note and then change whatever he likes.
//

import BakePlannerCore
import CoreData
import SwiftUI

// MARK: - On a variant: where it came from

/// "Variante von „Landbrot“", the note, and the way to the comparison.
struct VariantOriginRow: View {
    @ObservedObject var recipe: Recipe
    let origin: Recipe

    @State private var showsComparison = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundColor(Theme.accentText)
                    .accessibilityHidden(true)
                NavigationLink(destination: RecipePageView(recipe: origin)) {
                    Text("Variante von „\(origin.name)“")
                        .font(Theme.brandFont(15))
                        .foregroundColor(Theme.accentText)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            if let note = recipe.variantNote, !note.isEmpty {
                Text(note)
                    .font(Theme.bodyFont(15))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showsComparison = true
            } label: {
                Label("Vergleichen", systemImage: "arrow.left.arrow.right")
                    .font(Theme.brandFont(15))
            }
            .accessibilityIdentifier("recipe.compareWithOrigin")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .sheet(isPresented: $showsComparison) {
            RecipeComparisonSheet(origin: origin, variant: recipe)
        }
    }
}

// MARK: - The comparison

/// What the variant changes against its origin: the baker's note, then the
/// differences the app finds in the content (RecipeDifference).
struct RecipeComparisonSheet: View {
    let origin: Recipe
    let variant: Recipe

    @Environment(\.dismiss) private var dismiss

    private var difference: RecipeDifference {
        RecipeDifference.between(RecipeExportData(recipe: origin, includingImage: false),
                                 RecipeExportData(recipe: variant, includingImage: false))
    }

    var body: some View {
        NavigationStack {
            List {
                if let note = variant.variantNote, !note.isEmpty {
                    Section("Was ist anders") {
                        Text(note)
                    }
                }
                Section {
                    let lines = difference.lines()
                    if lines.isEmpty {
                        Text("Kein Unterschied zum Ursprungsrezept.")
                            .foregroundColor(Theme.subtitle)
                    } else {
                        ForEach(lines, id: \.self) { line in
                            Text(verbatim: line)
                        }
                    }
                } header: {
                    Text("Unterschiede zu „\(origin.name)“")
                }
            }
            .font(Theme.bodyFont(15))
            .navigationTitle(variant.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
}

// MARK: - On the origin: its variants

/// The origin's variants, each with what it changes and how it baked.
struct VariantsCard: View {
    @ObservedObject var recipe: Recipe

    private let dateFormat = DateFormat()

    var body: some View {
        let variants = recipe.variantsArray
        if !variants.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Varianten")
                    .font(Theme.brandFont(16))
                    .foregroundColor(Theme.title)

                let originContent = RecipeExportData(recipe: recipe, includingImage: false)
                ForEach(variants) { variant in
                    NavigationLink(destination: RecipePageView(recipe: variant)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(variant.name)
                                .font(Theme.brandFont(15))
                                .foregroundColor(Theme.cardTitle)
                                .multilineTextAlignment(.leading)

                            let change = Self.changeText(of: variant, originContent: originContent)
                            if !change.isEmpty {
                                Text(verbatim: change)
                                    .font(Theme.bodyFont(14))
                                    .foregroundColor(Theme.subtitle)
                                    .multilineTextAlignment(.leading)
                            }

                            Text(verbatim: Self.bakesText(of: variant, dateFormat: dateFormat))
                                .font(Theme.bodyFont(14))
                                .foregroundColor(Theme.cardTitle)
                                .multilineTextAlignment(.leading)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    /// The baker's note, or what the app finds different when there is none.
    static func changeText(of variant: Recipe, originContent: RecipeExportData) -> String {
        if let note = variant.variantNote, !note.isEmpty { return note }
        return RecipeDifference.between(originContent, RecipeExportData(recipe: variant, includingImage: false))
            .summary()
    }

    /// "3-mal gebacken · zuletzt 12.10.2026: ★★★★ · offen", or that the
    /// variant has not been baked yet. Only bakes that already happened.
    static func bakesText(of variant: Recipe, dateFormat: DateFormat, now: Date = Date()) -> String {
        let completed = variant.bakeHistoriesArray.filter { $0.date <= now }
        return RecipeVariantText.bakes(completedCount: completed.count,
                                       lastDateText: completed.first.map { dateFormat.calculateDate(dT: $0.date) } ?? "",
                                       lastFactsLine: completed.first?.facts.summaryLine() ?? "")
    }
}

// MARK: - A new variant by hand

/// Makes a copy of `origin` as its variant: the baker writes what he means
/// to change, the copy opens in the editor for the change itself.
struct NewVariantSheet: View {
    let origin: Recipe
    let onCreated: (NSManagedObjectID) -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("z. B. mehr Salz, längere Stockgare", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("variant.note")
                } header: {
                    Text("Was ist anders? (optional)")
                } footer: {
                    Text("Die Variante wird als Kopie von „\(origin.name)“ angelegt und bleibt mit dem Rezept verbunden: Ihre Backvorgänge erscheinen dort unter „Varianten“. Die Änderung selbst machst Du danach mit „Bearbeiten“.")
                }
            }
            .navigationTitle("Neue Variante")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") { create() }
                        .accessibilityIdentifier("variant.create")
                }
            }
            .alert("Speichern fehlgeschlagen", isPresented: $saveFailed) {
                Button("OK", role: .cancel) { }
            }
        }
    }

    private func create() {
        let copy = RecipeExportData(recipe: origin).makeRecipe(in: viewContext)
        copy.name = AdjustedRecipe.variantName(original: origin.name, among: Recipe.allNames(in: viewContext))
        copy.origin = origin
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.variantNote = trimmed.isEmpty ? nil : trimmed
        // Like an adjusted copy, so a flour swap or a TA change on the
        // variant changes it in place instead of stacking a copy on a copy.
        copy.adjustedOn = Date()
        do {
            try viewContext.save()
            onCreated(copy.objectID)
            dismiss()
        } catch {
            viewContext.rollback()
            saveFailed = true
        }
    }
}
