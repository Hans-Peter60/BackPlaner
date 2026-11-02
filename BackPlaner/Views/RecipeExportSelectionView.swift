//
//  RecipeExportSelectionView.swift
//  BackPlaner
//
//  "Rezepte exportieren" from the recipe list's "Mehr" menu: the user's own
//  recipes with a checkmark each, and the chosen ones leave as one backup
//  file — between the single recipe's "Rezept exportieren" on its page and
//  "Alle eigenen Rezepte sichern" in the settings. The bake history and the
//  starter diary go along only when asked: a file handed to someone else
//  carries the recipes alone, a partial backup carries everything.
//

import BakePlannerCore
import SwiftUI
import CoreData

struct RecipeExportSelectionView: View {

    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>

    @State private var selection: Set<NSManagedObjectID> = []
    @State private var includesBakeHistory = false

    private var allSelected: Bool {
        !recipes.isEmpty && selection.count == recipes.count
    }

    private var selectedRecipes: [Recipe] {
        recipes.filter { selection.contains($0.objectID) }
    }

    /// One recipe keeps its name as the file's; several get the backup's
    /// dated name.
    private var fileName: String {
        if selectedRecipes.count == 1, let name = selectedRecipes.first?.name, !name.isEmpty {
            return name
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "BakePlanner-Rezepte-\(formatter.string(from: Date()))"
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                // A row, not a toolbar button: beside the title, "Auswahl
                // aufheben" cut it to "Rezepte expor…".
                Button {
                    selection = allSelected ? [] : Set(recipes.map(\.objectID))
                } label: {
                    (allSelected ? Text("Auswahl aufheben") : Text("Alle auswählen"))
                        .font(Theme.brandFont(15))
                        .foregroundColor(Theme.accentText)
                }
                .selectionDisabled(true)

                ForEach(recipes) { recipe in
                    HStack(spacing: 12) {
                        RecipeThumbnail(data: recipe.image)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.name)
                                .font(Theme.bodyFont(16))
                            if !recipe.tags.isEmpty {
                                Text(recipe.tags.joined(separator: ", "))
                                    .font(Theme.bodyFont(13))
                                    .foregroundColor(Theme.subtitle)
                            }
                        }
                    }
                    .tag(recipe.objectID)
                }
            } footer: {
                Text("Die Auswahl wird als eine Datei exportiert, die ein anderes Gerät – iPhone, iPad oder Android – über „Aus Sicherung wiederherstellen“ einliest.")
            }

            Section {
                Toggle("Mit Backhistorie und Anstellgut-Tagebuch", isOn: $includesBakeHistory)
            }
        }
        // Always in edit mode: that is what draws the checkmarks.
        .environment(\.editMode, .constant(.active))
        .clearScrollBackground()
        .warmBackground()
        .navigationTitle("Rezepte exportieren")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // An X, not the word: with "Alle auswählen" on the other side
            // the title shrank to "Rezepte e…".
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen", systemImage: "xmark", role: .close) { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            exportButton
                .padding()
        }
    }

    /// The share sheet with the file; Pro, as the single recipe's export.
    private var exportButton: some View {
        ProGate(.recipeSharing) {
            ShareLink(
                item: RecipeFileExport(recipes: selectedRecipes, fileName: fileName,
                                       includesBakeHistory: includesBakeHistory),
                preview: SharePreview(Text("BakePlanner-Rezepte"))
            ) {
                exportLabel
            }
        } label: {
            exportLabel
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(selection.isEmpty)
        .accessibilityIdentifier("export.share")
    }

    private var exportLabel: some View {
        Label("Exportieren (\(selection.count))", systemImage: "doc.badge.arrow.up")
            .font(Theme.brandFont(16))
            .frame(maxWidth: .infinity)
    }
}

/// A recipe's picture, small, for a list row.
private struct RecipeThumbnail: View {
    let data: Data

    var body: some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
