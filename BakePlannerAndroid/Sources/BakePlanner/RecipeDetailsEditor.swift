import BakePlannerCore
import SwiftUI

/// Changes a recipe's name, description, rating and tags. Components,
/// ingredients and steps are left as they are.
struct RecipeDetailsEditor: View {
    let recipe: StoredRecipe
    let onSave: (StoredRecipe) -> Void
    @State var name: String
    @State var summary: String
    @State var rating: Int
    @State var tags: String
    @Environment(\.dismiss) var dismiss

    init(recipe: StoredRecipe, onSave: @escaping (StoredRecipe) -> Void) {
        self.recipe = recipe
        self.onSave = onSave
        _name = State(initialValue: recipe.content.name)
        _summary = State(initialValue: recipe.content.summary)
        _rating = State(initialValue: recipe.content.rating)
        _tags = State(initialValue: recipe.content.tags.joined(separator: ", "))
    }

    var body: some View {
        Form {
            Section {
                TextField("Rezeptname", text: $name)
            } header: {
                Text("Name")
            }

            Section {
                TextEditor(text: $summary)
                    .frame(minHeight: 100)
            } header: {
                Text("Beschreibung")
            }

            Section {
                Stepper(value: $rating, in: 0...5) {
                    Text(verbatim: rating == 0 ? "–" : String(repeating: "★", count: rating))
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Bewertung")
            }

            Section {
                TextField("Tags, durch Komma getrennt", text: $tags)
            } header: {
                Text("Tags")
            }
        }
        .navigationTitle("Bearbeiten")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    onSave(edited)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    /// The recipe with the fields of this form.
    private var edited: StoredRecipe {
        var edited = recipe
        edited.content.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.content.summary = summary
        edited.content.rating = rating
        edited.content.tags = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return edited
    }
}
