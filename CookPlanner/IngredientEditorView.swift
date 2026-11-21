//
//  IngredientEditorView.swift
//  CookPlanner
//
//  One ingredient's sheet in the dish editor: name, amount and unit as
//  the recipe gives them, the component it belongs to, a remark.
//

import BakePlannerCore
import SwiftUI

/// What the sheet edits, with the amount as text for the number pad.
struct IngredientDraft: Identifiable {
    let id: String
    let isNew: Bool
    var name: String
    var amountText: String
    var unit: String
    var component: String
    var note: String

    init(ingredient: KitchenIngredient?, isNew: Bool, component: String = "") {
        id = ingredient?.id ?? UUID().uuidString
        self.isNew = isNew
        name = ingredient?.name ?? ""
        amountText = ingredient?.amount.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? ""
        unit = ingredient?.unit ?? ""
        self.component = ingredient?.component ?? component
        note = ingredient?.note ?? ""
    }

    /// The amount as typed, with a comma or a point; nil when empty.
    var amount: Double? {
        let text = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty, let value = Double(text), value > 0 else { return nil }
        return value
    }

    var ingredient: KitchenIngredient {
        KitchenIngredient(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), amount: amount,
                          unit: unit.trimmingCharacters(in: .whitespaces),
                          component: component.trimmingCharacters(in: .whitespacesAndNewlines),
                          note: note.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct IngredientEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var draft: IngredientDraft
    @FocusState private var focused: Bool
    let components: [String]
    let onSave: (KitchenIngredient) -> Void
    let onDelete: () -> Void

    /// The units a recipe uses most, one tap each; anything else is typed.
    private static let units = ["g", "ml", "EL", "TL", "Stück", "Zweig", "Bund", "Prise"]

    init(draft: IngredientDraft, components: [String],
         onSave: @escaping (KitchenIngredient) -> Void, onDelete: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.components = components
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .focused($focused)
                    HStack {
                        TextField("Menge", text: $draft.amountText)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 90)
                        TextField("Einheit", text: $draft.unit)
                        Menu {
                            ForEach(Self.units, id: \.self) { unit in
                                Button(unit) { draft.unit = unit }
                            }
                            Button("Ohne Einheit") { draft.unit = "" }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .accessibilityLabel("Einheit wählen")
                    }
                    HStack {
                        TextField("Komponente", text: $draft.component)
                        if !components.isEmpty {
                            Menu {
                                ForEach(components, id: \.self) { component in
                                    Button(component) { draft.component = component }
                                }
                            } label: {
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .accessibilityLabel("Komponente wählen")
                        }
                    }
                    TextField("Hinweis", text: $draft.note)
                } header: {
                    Text("Zutat")
                } footer: {
                    Text("Menge und Einheit wie im Rezept; ohne Menge für „Salz“ oder „Pfeffer“.")
                }

                if !draft.isNew {
                    Section {
                        Button("Zutat löschen", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(draft.isNew ? "Neue Zutat" : "Zutat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        onSave(draft.ingredient)
                        dismiss()
                    }
                    .disabled(!draft.canSave)
                }
            }
            .onAppear { if draft.isNew { focused = true } }
        }
    }
}
