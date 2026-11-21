//
//  ShoppingListView.swift
//  CookPlanner
//
//  The dish's ingredients by component, to tick off while shopping. What
//  is ticked is kept per dish, so the list survives leaving the screen;
//  the share button hands the open items to Notes, Reminders or a message.
//

import BakePlannerCore
import SwiftUI

struct ShoppingListView: View {

    let dish: KitchenDish

    @Environment(\.dismiss) private var dismiss
    @State private var checked: Set<String> = []

    private var storageKey: String { "shopping.checked." + dish.id }
    private var groups: [(component: String, ingredients: [KitchenIngredient])] { KitchenShoppingList.groups(of: dish) }
    private var shareText: String { KitchenShoppingList.text(for: dish, excluding: checked) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.component) { group in
                    Section {
                        ForEach(group.ingredients) { ingredient in
                            Button {
                                toggle(ingredient.id)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Image(systemName: checked.contains(ingredient.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(Theme.accentText)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: ingredient.line())
                                            .strikethrough(checked.contains(ingredient.id))
                                            .foregroundColor(checked.contains(ingredient.id) ? .secondary : .primary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(verbatim: group.component.isEmpty ? String(localized: "Ohne Komponente") : group.component)
                    }
                }
                if dish.ingredients.isEmpty {
                    Text("Noch nichts zu kaufen: Das Gericht hat keine Zutaten.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Einkaufsliste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button("Alle abhaken") {
                            checked = Set(dish.ingredients.map(\.id))
                            save()
                        }
                        Button("Zurücksetzen") {
                            checked = []
                            save()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Mehr")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText, subject: Text(verbatim: dish.name)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Teilen")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func toggle(_ id: String) {
        if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
        save()
    }

    private func load() {
        checked = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
    }

    private func save() {
        UserDefaults.standard.set(Array(checked), forKey: storageKey)
    }
}
