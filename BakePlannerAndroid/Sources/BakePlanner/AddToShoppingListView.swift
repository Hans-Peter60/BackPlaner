import BakePlannerCore
import SwiftUI

/// Puts a recipe's ingredients, at the amount chosen in the recipe, on a new
/// list for a day or on one of the lists there are — as the iPhone's
/// "Einkaufsliste" tab does.
struct AddToShoppingListView: View {
    let model: AppModel
    let recipeID: String
    /// The factor chosen in the recipe: 1 is the recipe as stored.
    let scale: Double
    @State var addsToExistingList = false
    @State var date = Date()
    /// What the last addition did. Kept apart from the alert's visibility:
    /// Android closes the alert before it runs the chosen button.
    @State var outcome: AppModel.ShoppingListOutcome?
    @State var showsOutcome = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section {
                Picker("Ziel", selection: $addsToExistingList) {
                    Text("Neue Liste").tag(false)
                    Text("Bestehende Liste").tag(true)
                }
                .pickerStyle(.segmented)

                if scale != 1 {
                    Text("Die Mengen entsprechen dem Faktor \(RecipeDetailView.factorText(scale)).")
                        .font(.caption)
                }
            }

            if addsToExistingList {
                Section {
                    if model.shoppingLists.isEmpty {
                        Text("Keine Einkaufsliste vorhanden")
                        Text("Erstelle zuerst eine neue Liste.")
                            .font(.caption)
                    } else {
                        ForEach(model.shoppingLists, id: \.id) { list in
                            Button {
                                add(to: .existingList(list.id))
                            } label: {
                                ShoppingListRow(list: list)
                                    .foregroundStyle(Color.primary)
                            }
                        }
                    }
                } header: {
                    Text("Bestehende Einkaufslisten")
                }
            } else {
                Section {
                    DatePicker("Datum", selection: $date, displayedComponents: [.date])
                    Button("Erstellen") {
                        add(to: .newList(date))
                    }
                }
            }
        }
        .navigationTitle("Einkaufsliste erstellen")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
        }
        .alert(outcomeTitle, isPresented: $showsOutcome) {
            Button {
                if outcome == .added { dismiss() }
                outcome = nil
            } label: {
                Text(verbatim: "OK")
            }
        } message: {
            if outcome == .nothingToBuy {
                Text("Für dieses Rezept sind keine Zutaten hinterlegt, die auf eine Einkaufsliste passen.")
            }
        }
    }

    private func add(to target: AppModel.ShoppingListTarget) {
        outcome = model.addToShoppingList(recipeID: recipeID, scale: scale, target: target)
        showsOutcome = true
    }

    private var outcomeTitle: LocalizedStringKey {
        switch outcome {
        case .added: return "Zutaten wurden auf die Einkaufsliste gesetzt"
        case .nothingToBuy: return "Keine Zutaten vorhanden"
        case .failed, nil: return "Die Änderung konnte nicht gespeichert werden."
        }
    }
}
