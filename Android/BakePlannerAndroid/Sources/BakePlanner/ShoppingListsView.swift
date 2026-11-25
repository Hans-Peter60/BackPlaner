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
            WarmBackdrop()
                .ignoresSafeArea()

            if model.shoppingLists.isEmpty {
                VStack(spacing: 12) {
                    Text("Keine Einkaufslisten")
                        .font(AppFont.title2)
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
        .navigationBarTitleDisplayMode(.inline)
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
                .font(AppFont.headline)
            if !list.recipeNames.isEmpty {
                Text(verbatim: list.recipeNames.joined(separator: ", "))
                    .font(AppFont.caption)
            }
            Text("\(list.items.count) Zutaten")
                .font(AppFont.caption)
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
    /// The lines about to be booked into the pantry: one line from its
    /// editor, or the whole list from the toolbar.
    @State var intakeItems: [StoredShoppingListItem] = []
    @State var intakes = false
    /// What the whole-list intake did, until the user has seen it.
    @State var intakeResult: AppModel.PantryIntakeResult?
    @State var showsIntakeResult = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    private var list: StoredShoppingList? {
        model.shoppingLists.first { $0.id == listID }
    }

    private var titleDate: String {
        list.map { ShoppingListText.date($0.date) } ?? ""
    }

    var body: some View {
        ZStack {
            WarmBackdrop()
                .ignoresSafeArea()

            if let list {
                content(of: list)
            }
        }
        .navigationTitle("Einkaufsliste vom \(titleDate)")
        .toolbar {
            // Everything bought: every line into the pantry, the list is
            // done with.
            if let list, !list.items.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Eingekauft") {
                        // In the order of the list: by shelf, then by name.
                        intakeItems = ShoppingListCategory.shelves(list.items, name: { $0.name }).flatMap(\.items)
                        intakes = true
                    }
                }
            }
        }
        .appSheet(isPresented: $editsItem) {
            if let item = editedItem {
                NavigationStack {
                    ShoppingListItemEditor(item: item,
                                           onSave: { model.update($0) },
                                           onRemove: { model.deleteShoppingListItem(id: item.id) },
                                           onReceive: { receive([item]) })
                }
            }
        }
        .appSheet(isPresented: $intakes) {
            NavigationStack {
                ShoppingListIntakeSheet(model: model, listID: listID, items: intakeItems) { result in
                    if intakeItems.count > 1 {
                        intakeResult = result
                        showsIntakeResult = true
                    } else if result.finished {
                        // The last line went into the pantry and the list
                        // with it: nothing is left to show here.
                        dismiss()
                    }
                }
            }
        }
        .alert("In den Vorrat gebucht", isPresented: $showsIntakeResult) {
            Button {
                // A list done with is gone; leave its page.
                if intakeResult?.finished == true {
                    dismiss()
                }
                intakeResult = nil
            } label: {
                Text(verbatim: "OK")
            }
        } message: {
            // The singular as its own text: the Android catalog carries no
            // plural rules.
            if let result = intakeResult {
                if result.finished {
                    if result.booked == 1 {
                        Text("Eine Zeile ist im Vorrat. Die Einkaufsliste ist erledigt.")
                    } else {
                        Text("\(result.booked) Zeilen sind im Vorrat. Die Einkaufsliste ist erledigt.")
                    }
                } else if result.booked == 1 {
                    Text("Eine Zeile ist im Vorrat. Nicht gekaufte Zeilen bleiben auf der Liste.")
                } else {
                    Text("\(result.booked) Zeilen sind im Vorrat. Nicht gekaufte Zeilen bleiben auf der Liste.")
                }
            }
        }
    }

    /// Opens the "Eingekauft" sheet for these lines once the editor's
    /// sheet has gone.
    private func receive(_ items: [StoredShoppingListItem]) {
        intakeItems = items
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            intakes = true
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
    /// Books the line into the pantry; the sheet "Eingekauft" asks for the
    /// bought amount first.
    let onReceive: () -> Void
    @State var amount: String
    @State var unit: String
    @Environment(\.dismiss) var dismiss

    init(item: StoredShoppingListItem, onSave: @escaping (StoredShoppingListItem) -> Void,
         onRemove: @escaping () -> Void, onReceive: @escaping () -> Void) {
        self.item = item
        self.onSave = onSave
        self.onRemove = onRemove
        self.onReceive = onReceive
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
                    .font(AppFont.headline)
                HStack {
                    TextField("Menge", text: $amount)
                        .frame(width: 96)
                        .foregroundStyle(value != nil ? Color.primary : Color.red)
                    TextField("Einheit", text: $unit)
                }
                Text("Die Menge gilt für diese Einkaufsliste. Das Rezept bleibt unverändert.")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("In den Vorrat übernehmen") {
                    onReceive()
                    dismiss()
                }
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

    /// How a line reads: the package to buy, the recipe's need in brackets
    /// — "1 kg Weizenmehl 550 (200 g)" — or just the need, "1/2 Würfel
    /// Hefe", when there is no standard package or the package is the need.
    static func line(_ item: StoredShoppingListItem) -> String {
        let needed = neededText(item)
        guard let package = package(for: item) else { return needed + item.name }
        return PantryText.amountText(amount: package.amount, unit: package.unit) + " " + item.name
            + " (" + needed.trimmingCharacters(in: .whitespaces) + ")"
    }

    /// The recipe's amount as the row always showed it, with a trailing space.
    static func neededText(_ item: StoredShoppingListItem) -> String {
        Rational.getPortion(unit: item.unit ?? "", weight: item.weight, num: item.num, denom: item.denom,
                            targetServings: 2)
    }

    /// What the line needs in pantry terms: grams, kilograms or pieces.
    static func need(for item: StoredShoppingListItem) -> (amount: Double, unit: PantryUnit) {
        Pantry.intake(unit: item.unit, weight: item.weight, normWeight: item.normWeight, num: item.num, denom: item.denom)
    }

    /// The standard package covering the need, when there is one and it is
    /// more than the need itself.
    static func package(for item: StoredShoppingListItem) -> (amount: Double, unit: PantryUnit)? {
        let need = need(for: item)
        guard let package = PackageSizes.package(name: item.name, amount: need.amount, unit: need.unit),
              PackageSizes.differs(package, from: need.amount, unit: need.unit) else { return nil }
        return package
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
