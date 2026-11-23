//
//  ShoppingListView.swift
//  CookPlanner
//
//  The dish's ingredients by component. Tick what is at home already; the
//  rest is what to buy, and "Fehlendes teilen" hands exactly that to
//  Reminders, Notes or a message, one ingredient per line. What is ticked
//  is kept per dish, so the list survives leaving the screen.
//

import BakePlannerCore
import SwiftUI

struct ShoppingListView: View {

    let dish: KitchenDish

    @Environment(\.dismiss) private var dismiss
    @State private var checked: Set<String> = []

    private var storageKey: String { "shopping.checked." + dish.id }
    private var groups: [(component: String, ingredients: [KitchenIngredient])] { KitchenShoppingList.groups(of: dish) }
    private var shareText: String { KitchenShoppingList.missingText(for: dish, available: checked) }
    private var missingCount: Int { dish.ingredients.filter { !checked.contains($0.id) }.count }

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
            .safeAreaInset(edge: .top) {
                if !dish.ingredients.isEmpty {
                    Text("Hake ab, was Du schon im Haus hast. Den Rest teilst Du unten, z. B. an Erinnerungen.")
                        .font(Theme.bodyFont(13))
                        .foregroundColor(Theme.subtitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !dish.ingredients.isEmpty {
                    ShareLink(item: shareText, subject: Text(verbatim: dish.name)) {
                        Label(missingCount == 0 ? "Alles im Haus" : "Fehlendes teilen (\(missingCount))",
                              systemImage: missingCount == 0 ? "checkmark.circle" : "square.and.arrow.up")
                            .font(Theme.bodyFont(17).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentBottom)
                    .disabled(missingCount == 0)
                    .padding()
                }
            }
            .navigationTitle("Einkaufsliste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button("Alles im Haus") {
                            checked = Set(dish.ingredients.map(\.id))
                            save()
                        }
                        Button("Nichts im Haus") {
                            checked = []
                            save()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Mehr")
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
