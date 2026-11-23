//
//  ShoppingListView.swift
//  CookPlanner
//
//  What to buy for the dish: one line per thing — the butter of three
//  components is one line with the amounts added up (KitchenShoppingList.
//  lines) — by shelf, as BakePlanner sorts its list. Tick what is at home already; the
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
    /// The same ingredient of several components is one line, amounts added up.
    private var lines: [KitchenShoppingList.Line] { KitchenShoppingList.lines(of: dish) }
    private var shelves: [ShoppingListCategory.Shelf<KitchenShoppingList.Line>] {
        ShoppingListCategory.shelves(lines, name: \.name)
    }
    private var shareText: String { KitchenShoppingList.missingLines(for: dish, available: checked) }
    private var missingCount: Int { lines.filter { !$0.ingredientIDs.allSatisfy(checked.contains) }.count }

    var body: some View {
        NavigationStack {
            List {
                // One line per thing to buy, by shelf in the order of a walk
                // through the shop; the components that use it in small print.
                ForEach(shelves) { shelf in
                    Section {
                        ForEach(shelf.items) { line in
                            let atHome = line.ingredientIDs.allSatisfy(checked.contains)
                            Button {
                                toggle(line)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Image(systemName: atHome ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(Theme.accentText)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: line.text())
                                            .strikethrough(atHome)
                                            .foregroundColor(atHome ? .secondary : .primary)
                                        if line.components.count > 1 || dish.components.count > 1 {
                                            Text(verbatim: line.components.joined(separator: " · "))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Label(shelf.category.title, systemImage: shelf.category.systemImage)
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

    /// A line stands for every ingredient of that name: all at home, or none.
    private func toggle(_ line: KitchenShoppingList.Line) {
        if line.ingredientIDs.allSatisfy(checked.contains) {
            checked.subtract(line.ingredientIDs)
        } else {
            checked.formUnion(line.ingredientIDs)
        }
        save()
    }

    private func load() {
        checked = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
    }

    private func save() {
        UserDefaults.standard.set(Array(checked), forKey: storageKey)
    }
}
