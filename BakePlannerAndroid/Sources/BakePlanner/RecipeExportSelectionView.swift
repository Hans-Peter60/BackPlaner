import SwiftUI

/// "Rezepte exportieren" from the recipe list's "Mehr" menu, as on the
/// iPhone: the own recipes with a checkmark each, and the chosen ones leave
/// as one backup file — between a recipe's own export on its page and
/// "Alle eigenen Rezepte sichern". The bake history and the starter diary
/// go along only when asked: a file handed to someone else carries the
/// recipes alone, a partial backup carries everything.
///
/// The sheet only collects the choice; the list view behind it runs the
/// exporter (RecipeFileExporter) once the sheet is gone, so the system's
/// "save as" does not open over a closing sheet.
struct RecipeExportSelectionView: View {
    let model: AppModel
    /// The chosen recipe ids and whether the bake history goes along.
    let onExport: ([String], Bool) -> Void

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State var selection: Set<String> = []
    @State var includesBakeHistory = false

    var allSelected: Bool {
        !model.recipes.isEmpty && selection.count == model.recipes.count
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    // A row, not a toolbar button, as on the iPhone.
                    Button {
                        selection = allSelected ? [] : Set(model.recipes.map(\.id))
                    } label: {
                        (allSelected ? Text("Auswahl aufheben") : Text("Alle auswählen"))
                            .foregroundStyle(Palette.accent(colorScheme))
                    }
                    .buttonStyle(.plain)

                    ForEach(model.recipes, id: \.id) { recipe in
                        Button {
                            if selection.contains(recipe.id) {
                                selection.remove(recipe.id)
                            } else {
                                selection.insert(recipe.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                RecipeRow(model: model, recipe: recipe)
                                Spacer()
                                // The outlined check circle stands for "not
                                // chosen": SkipUI has no plain "circle".
                                Image(systemName: selection.contains(recipe.id) ? "checkmark.circle.fill" : "checkmark.circle")
                                    .foregroundStyle(selection.contains(recipe.id) ? Palette.accent(colorScheme) : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Die Auswahl wird als eine Datei exportiert, die ein anderes Gerät – iPhone, iPad oder Android – über „Aus Sicherung wiederherstellen“ einliest.")
                }

                Section {
                    Toggle("Mit Backhistorie und Anstellgut-Tagebuch", isOn: $includesBakeHistory)
                }
            }

            Button {
                let ids = model.recipes.map(\.id).filter { selection.contains($0) }
                let history = includesBakeHistory
                dismiss()
                onExport(ids, history)
            } label: {
                Text("Exportieren (\(selection.count))")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent(colorScheme))
            .disabled(selection.isEmpty)
            .padding()
        }
        .navigationTitle("Rezepte exportieren")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen") {
                    dismiss()
                }
            }
        }
    }
}
