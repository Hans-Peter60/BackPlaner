import BakePlannerCore
import SwiftUI

/// The shopping lists by date, oldest first, each with its recipes and the
/// number of its lines. Swiping removes a list.
struct ShoppingListsView: View {
    let model: AppModel
    /// The list waiting for the user to confirm its removal. Kept apart
    /// from the dialog's visibility: Android closes the dialog before it
    /// runs the chosen button.
    @State var listToDelete: StoredShoppingList?
    @State var confirmsDeletion = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.backgroundTop(colorScheme), Palette.backgroundBottom(colorScheme)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if model.shoppingLists.isEmpty {
                VStack(spacing: 12) {
                    Text("Keine Einkaufslisten")
                        .font(.title2)
                        .foregroundStyle(Palette.accent(colorScheme))
                    Text("Öffne ein Rezept und tippe auf „Rezept zur Einkaufsliste hinzufügen“.")
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List {
                    ForEach(model.shoppingLists, id: \.id) { list in
                        NavigationLink {
                            ShoppingListDetailView(model: model, listID: list.id)
                        } label: {
                            ShoppingListRow(list: list)
                        }
                    }
                    .onDelete { offsets in
                        listToDelete = offsets.first.map { model.shoppingLists[$0] }
                        confirmsDeletion = listToDelete != nil
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Einkaufslisten")
        .alert("Einkaufsliste löschen", isPresented: $confirmsDeletion) {
            Button("Löschen", role: .destructive) {
                if let list = listToDelete {
                    model.deleteShoppingList(id: list.id)
                }
                listToDelete = nil
            }
            Button("Abbrechen", role: .cancel) {
                listToDelete = nil
            }
        } message: {
            if let list = listToDelete {
                Text("Einkaufsliste vom \(ShoppingListText.date(list.date))")
            }
        }
    }
}

/// One list in the overview: its date, its recipes, how many lines.
struct ShoppingListRow: View {
    let list: StoredShoppingList

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Einkaufsliste vom \(ShoppingListText.date(list.date))")
                .font(.headline)
            if !list.recipeNames.isEmpty {
                Text(verbatim: list.recipeNames.joined(separator: ", "))
                    .font(.caption)
            }
            Text("\(list.items.count) Zutaten")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One shopping list: its recipes, then its lines grouped by shelf in the
/// order of a walk through the shop. Tapping a line changes its amount,
/// swiping removes it.
struct ShoppingListDetailView: View {
    let model: AppModel
    let listID: String
    /// The line being changed. Kept apart from the sheet's visibility, as
    /// the dialogs are.
    @State var editedItem: StoredShoppingListItem?
    @State var editsItem = false
    @Environment(\.colorScheme) var colorScheme

    private var list: StoredShoppingList? {
        model.shoppingLists.first { $0.id == listID }
    }

    private var titleDate: String {
        list.map { ShoppingListText.date($0.date) } ?? ""
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.backgroundTop(colorScheme), Palette.backgroundBottom(colorScheme)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if let list {
                content(of: list)
            }
        }
        .navigationTitle("Einkaufsliste vom \(titleDate)")
        .sheet(isPresented: $editsItem) {
            if let item = editedItem {
                NavigationStack {
                    ShoppingListItemEditor(item: item,
                                           onSave: { model.update($0) },
                                           onRemove: { model.deleteShoppingListItem(id: item.id) })
                }
            }
        }
    }

    private func content(of list: StoredShoppingList) -> some View {
        let shelves = ShoppingListCategory.shelves(list.items, name: { $0.name })
        return List {
            if !list.recipeNames.isEmpty {
                Section {
                    ForEach(list.recipeNames, id: \.self) { name in
                        Text(verbatim: name)
                    }
                } header: {
                    Text("Rezepte")
                }
            }

            if list.items.isEmpty {
                Text("Noch keine Zutaten")
                    .foregroundStyle(.secondary)
            }

            ForEach(shelves, id: \.category.rawValue) { shelf in
                Section {
                    ForEach(shelf.items, id: \.id) { item in
                        Button {
                            editedItem = item
                            editsItem = true
                        } label: {
                            Text(verbatim: ShoppingListText.line(item))
                                .foregroundStyle(Color.primary)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            model.deleteShoppingListItem(id: shelf.items[index].id)
                        }
                    }
                } header: {
                    Text(shelf.category.title)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

/// Changes the amount and unit of one line. The name stays: lines of the
/// same name are merged when another recipe is added, so renaming one would
/// split it off.
struct ShoppingListItemEditor: View {
    let item: StoredShoppingListItem
    let onSave: (StoredShoppingListItem) -> Void
    let onRemove: () -> Void
    @State var amount: String
    @State var unit: String
    @Environment(\.dismiss) var dismiss

    init(item: StoredShoppingListItem, onSave: @escaping (StoredShoppingListItem) -> Void,
         onRemove: @escaping () -> Void) {
        self.item = item
        self.onSave = onSave
        self.onRemove = onRemove
        _amount = State(initialValue: IngredientAmountText.text(weight: item.weight, numerator: item.num,
                                                                denominator: item.denom))
        _unit = State(initialValue: item.unit ?? "")
    }

    /// The amount typed, nil while it cannot be read ("250", "1,5", "1/4").
    private var value: IngredientAmountText? {
        IngredientAmountText.parse(amount)
    }

    var body: some View {
        Form {
            Section {
                Text(verbatim: item.name)
                    .font(.headline)
                HStack {
                    TextField("Menge", text: $amount)
                        .frame(width: 96)
                        .foregroundStyle(value != nil ? Color.primary : Color.red)
                    TextField("Einheit", text: $unit)
                }
                Text("Die Menge gilt für diese Einkaufsliste. Das Rezept bleibt unverändert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Zutat entfernen", role: .destructive) {
                    onRemove()
                    dismiss()
                }
            }
        }
        .navigationTitle("Menge ändern")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") {
                    if let changed = changedItem {
                        onSave(changed)
                    }
                    dismiss()
                }
                .disabled(value == nil)
            }
        }
    }

    /// The line with the new amount, its weight in the base unit worked out
    /// again as on the iPhone: lines are merged and converted by it.
    private var changedItem: StoredShoppingListItem? {
        guard let value else { return nil }
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = item
        changed.unit = trimmedUnit.isEmpty ? nil : trimmedUnit
        changed.weight = value.weight
        changed.num = value.numerator
        changed.denom = value.denominator
        changed.normWeight = CalcIngredientWeight().calcIngredientWeight(
            weight: value.weight, unit: trimmedUnit, name: item.name, num: value.numerator, denom: value.denominator)
        return changed
    }
}

/// How dates and lines of a shopping list read, as on the iPhone.
enum ShoppingListText {
    /// "31.10.26" in the app's language.
    static func date(_ date: Date) -> String {
        DateFormat().calculateDate(dT: date)
    }

    /// "500 g Weizenmehl 550", "1/2 Würfel Hefe".
    static func line(_ item: StoredShoppingListItem) -> String {
        Rational.getPortion(unit: item.unit ?? "", weight: item.weight, num: item.num, denom: item.denom,
                            targetServings: 2) + item.name
    }
}

extension ShoppingListCategory {
    /// The heading above the shelf; the same texts as on the iPhone.
    var title: LocalizedStringKey {
        switch self {
        case .flourAndGrain:        return "Mehl & Getreide"
        case .dairyAndEggs:         return "Milchprodukte & Eier"
        case .bakingSupplies:       return "Backzutaten"
        case .nutsSeedsDriedFruit:  return "Nüsse, Saaten & Trockenfrüchte"
        case .fruitAndVegetables:   return "Obst & Gemüse"
        case .spicesAndHerbs:       return "Gewürze & Kräuter"
        case .fatsAndLiquids:       return "Öle, Fette & Flüssiges"
        case .other:                return "Sonstiges"
        }
    }
}
