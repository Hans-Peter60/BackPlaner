import BakePlannerCore
import SwiftUI

/// What to buy for the dish, as on the iPhone: one line per thing (the
/// butter of three components is one line, amounts added up), by shelf.
/// Tick what is at home; "Fehlendes teilen" hands the rest on as text.
/// The ticks are kept per dish.
struct ShoppingListView: View {
    let dish: KitchenDish
    @State var checked: Set<String> = []
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    private var key: String { "shopping.checked." + dish.id }
    private var lines: [KitchenShoppingList.Line] { KitchenShoppingList.lines(of: dish) }
    private var missingCount: Int { lines.filter { !$0.ingredientIDs.allSatisfy(checked.contains) }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(String(localized: "Hake ab, was Du schon im Haus hast. Den Rest teilst Du unten, z. B. an Erinnerungen.", bundle: .module))
                        .font(.footnote)
                        .foregroundStyle(Palette.subtitle(colorScheme))
                }
                ForEach(ShoppingListCategory.shelves(lines, name: { $0.name }), id: \.id) { shelf in
                    Section(shelf.category.shelfTitle) {
                        ForEach(shelf.items, id: \.id) { line in
                            Button {
                                toggle(line)
                            } label: {
                                ShoppingLineRow(line: line, atHome: line.ingredientIDs.allSatisfy(checked.contains),
                                                showsComponents: line.components.count > 1 || dish.components.count > 1)
                            }
                        }
                    }
                }
                Section {
                    ShareLink(item: KitchenShoppingList.missingLines(for: dish, available: checked)) {
                        Text(missingCount == 0 ? String(localized: "Alles im Haus", bundle: .module)
                                               : String(localized: "Fehlendes teilen (\(missingCount))", bundle: .module))
                    }
                    .disabled(missingCount == 0)
                    Button(String(localized: "Alles im Haus", bundle: .module)) {
                        checked = Set(dish.ingredients.map { $0.id })
                        save()
                    }
                    Button(String(localized: "Nichts im Haus", bundle: .module)) {
                        checked = []
                        save()
                    }
                }
            }
            .navigationTitle(String(localized: "Einkaufsliste", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Fertig", bundle: .module)) { dismiss() }
                }
            }
            .onAppear {
                let stored = SettingsFile.text(key) ?? ""
                checked = Set(stored.split(separator: "\n").map(String.init))
            }
        }
        .tint(Palette.accent(colorScheme))
    }

    private func toggle(_ line: KitchenShoppingList.Line) {
        if line.ingredientIDs.allSatisfy(checked.contains) {
            checked.subtract(line.ingredientIDs)
        } else {
            checked.formUnion(line.ingredientIDs)
        }
        save()
    }

    /// One line per id: Android's UserDefaults has no string arrays, and the
    /// settings file keeps texts.
    private func save() {
        SettingsFile.set(checked.isEmpty ? nil : checked.sorted().joined(separator: "\n"), forKey: key)
    }
}

struct ShoppingLineRow: View {
    let line: KitchenShoppingList.Line
    let atHome: Bool
    let showsComponents: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: atHome ? "checkmark.circle.fill" : "checkmark.circle")
                .foregroundStyle(atHome ? Palette.accentText(colorScheme) : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.text(locale: AppSettings.locale))
                    .strikethrough(atHome)
                    .foregroundStyle(atHome ? Color.secondary : Palette.title(colorScheme))
                if showsComponents {
                    Text(line.components.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

extension ShoppingListCategory {
    /// The shelf's heading, as on the iPhone.
    var shelfTitle: String {
        switch self {
        case .flourAndGrain: String(localized: "Mehl & Getreide", bundle: .module)
        case .dairyAndEggs: String(localized: "Milchprodukte & Eier", bundle: .module)
        case .bakingSupplies: String(localized: "Backzutaten", bundle: .module)
        case .nutsSeedsDriedFruit: String(localized: "Nüsse, Saaten & Trockenfrüchte", bundle: .module)
        case .fruitAndVegetables: String(localized: "Obst & Gemüse", bundle: .module)
        case .spicesAndHerbs: String(localized: "Gewürze & Kräuter", bundle: .module)
        case .fatsAndLiquids: String(localized: "Öle, Fette & Flüssiges", bundle: .module)
        case .other: String(localized: "Sonstiges", bundle: .module)
        }
    }
}
