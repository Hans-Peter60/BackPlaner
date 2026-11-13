import BakePlannerCore
import SwiftUI

/// The pantry: what is in the house, by shelf as the shopping list groups
/// it, with the items that run out soon on top and the last deductions of
/// ended plans at the bottom. Shown from the "Mehr" menu, as on the iPhone.
struct PantryView: View {
    let model: AppModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            WarmBackdrop()
                .ignoresSafeArea()

            if model.pantryItems.isEmpty && model.pantryBookings.isEmpty {
                VStack(spacing: 12) {
                    Text("Noch nichts im Vorrat")
                        .font(AppFont.title2)
                        .foregroundStyle(Palette.accent(colorScheme))
                    Text("Lege Mehle, Saaten und Hefe mit Menge und Mindesthaltbarkeit an. Aus der Einkaufsliste wandert Gekauftes mit einem Tipp hierher.")
                        .multilineTextAlignment(.center)
                    NavigationLink {
                        PantryItemEditor(model: model, item: nil)
                    } label: {
                        Text("Posten hinzufügen")
                    }
                    .buttonStyle(.bordered)
                    .tint(Palette.accent(colorScheme))
                }
                .padding()
            } else {
                list
            }
        }
        .navigationTitle("Vorrat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fertig") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    PantryItemEditor(model: model, item: nil)
                } label: {
                    Label("Posten hinzufügen", systemImage: "plus")
                }
            }
        }
    }

    private var list: some View {
        let attention = Pantry.needingAttention(model.pantryItems)
        let shelves = ShoppingListCategory.shelves(model.pantryItems, name: { $0.name })
        return List {
            if !attention.isEmpty {
                Section {
                    ForEach(attention, id: \.id) { item in
                        row(item)
                    }
                } header: {
                    Text("Bald aufbrauchen")
                }
            }
            ForEach(shelves, id: \.category.rawValue) { shelf in
                Section {
                    ForEach(shelf.items, id: \.id) { item in
                        row(item)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            model.deletePantryItem(id: shelf.items[index].id)
                        }
                    }
                } header: {
                    Text(shelf.category.title)
                }
            }
            if !model.pantryBookings.isEmpty {
                Section {
                    ForEach(model.pantryBookings, id: \.id) { booking in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: "\(booking.recipeName): \(PantryText.amountText(amount: booking.amount, unit: booking.unit)) \(booking.itemName)")
                                    .font(AppFont.subheadline)
                                Text(verbatim: ShoppingListText.date(booking.date))
                                    .font(AppFont.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Rückgängig") {
                                model.undoPantryBooking(booking)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("Letzte Abbuchungen")
                } footer: {
                    Text("Was ein beendeter Plan verbraucht hat. „Rückgängig“ bucht die Menge zurück, wenn das Brot doch nicht gebacken wurde.")
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ item: StoredPantryItem) -> some View {
        NavigationLink {
            PantryItemEditor(model: model, item: item)
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.name)
                        .font(AppFont.headline)
                    shelfLifeText(item)
                    // What open plans have already claimed of it.
                    let reserved = PantryLedger.reservedAmount(of: item, reservations: model.pantryReservations)
                    if reserved > 0 {
                        Text("davon \(PantryText.amountText(amount: reserved, unit: item.unit)) reserviert")
                            .font(AppFont.caption)
                            .foregroundStyle(reserved > item.amount ? Palette.warning(colorScheme) : Palette.subtitle(colorScheme))
                    }
                    if !item.note.isEmpty {
                        Text(verbatim: item.note)
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(verbatim: PantryText.amountText(item))
                    .font(AppFont.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Haltbar bis 20.11.26", coloured when it is soon or over.
    @ViewBuilder
    private func shelfLifeText(_ item: StoredPantryItem) -> some View {
        if let bestBefore = item.bestBefore {
            let date = ShoppingListText.date(bestBefore)
            switch PantryShelfLife.of(bestBefore) {
            case .unknown:
                EmptyView()
            case .fresh:
                Text("Haltbar bis \(date)")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            case .soon(let days):
                if days == 0 {
                    Text("Läuft heute ab")
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.warning(colorScheme))
                } else {
                    Text("Läuft in \(days) Tagen ab (\(date))")
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.warning(colorScheme))
                }
            case .expired(let days):
                Text("Seit \(days) Tagen abgelaufen (\(date))")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.danger(colorScheme))
            }
        }
    }
}

/// One pantry item: name with suggestions from the recipes, amount and
/// unit, the best-before date, a note.
struct PantryItemEditor: View {
    let model: AppModel
    let item: StoredPantryItem?
    @State var name: String
    @State var amount: String
    @State var unit: PantryUnit
    @State var hasBestBefore: Bool
    @State var bestBefore: Date
    @State var note: String
    @State var saveFailed = false
    /// The names of the recipes' bought ingredients, most used first; read
    /// once, not on every keystroke.
    @State var suggestions: [String] = []
    @Environment(\.dismiss) var dismiss

    init(model: AppModel, item: StoredPantryItem?) {
        self.model = model
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _amount = State(initialValue: PantryText.number(item?.amount ?? 1_000))
        _unit = State(initialValue: item?.unit ?? .gram)
        _hasBestBefore = State(initialValue: item?.bestBefore != nil)
        _bestBefore = State(initialValue: item?.bestBefore ?? Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date())
        _note = State(initialValue: item?.note ?? "")
    }

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The amount typed, nil while it cannot be read ("250", "1,5").
    private var value: Double? { PantryText.parse(amount) }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                // Names from the recipes, so the pantry and the recipes
                // agree on what "Weizenmehl 550" is called; shown while the
                // name is still being typed.
                if item == nil || cleanName != item?.name {
                    let matching = Array(Pantry.matchingNames(name, in: suggestions).prefix(6))
                    ForEach(matching, id: \.self) { suggestion in
                        Button {
                            name = suggestion
                        } label: {
                            Text(verbatim: suggestion)
                                .font(AppFont.subheadline)
                                .foregroundStyle(Color.primary)
                        }
                    }
                }
            } header: {
                Text("Zutat")
            } footer: {
                if item == nil && !suggestions.isEmpty {
                    Text("Vorschläge aus Deinen Rezepten")
                }
            }
            Section {
                HStack {
                    TextField("Menge", text: $amount)
                        .frame(width: 96)
                        .foregroundStyle(value != nil ? Color.primary : Color.red)
                    Picker("Einheit", selection: $unit) {
                        ForEach(PantryUnit.allCases) { unit in
                            Text(verbatim: PantryText.unitTitle(unit)).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Menge")
            }
            Section {
                Toggle("Mindesthaltbarkeit", isOn: $hasBestBefore)
                if hasBestBefore {
                    DatePicker("Haltbar bis", selection: $bestBefore, displayedComponents: [.date])
                }
            }
            Section {
                TextField("Mühle, Sorte, angebrochen …", text: $note)
            } header: {
                Text("Notiz")
            }
            if let item {
                Section {
                    Button("Aus dem Vorrat entfernen", role: .destructive) {
                        model.deletePantryItem(id: item.id)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(item == nil ? "Neuer Posten" : "Posten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") {
                    save()
                }
                .disabled(cleanName.isEmpty || value == nil)
            }
        }
        .task {
            suggestions = model.pantrySuggestions
        }
        .alert("Sichern fehlgeschlagen", isPresented: $saveFailed) {
            Button {
            } label: {
                Text(verbatim: "OK")
            }
        }
    }

    private func save() {
        guard let value else { return }
        let date = hasBestBefore ? bestBefore : nil
        let saved: Bool
        if var existing = item {
            existing.name = cleanName
            existing.amount = value
            existing.unit = unit
            existing.bestBefore = date
            existing.note = note
            saved = model.updatePantryItem(existing)
        } else {
            saved = model.addPantryItem(name: cleanName, amount: value, unit: unit, bestBefore: date, note: note)
        }
        if saved {
            dismiss()
        } else {
            saveFailed = true
        }
    }
}

/// How pantry amounts read and are typed, as on the iPhone.
enum PantryText {
    static func unitTitle(_ unit: PantryUnit) -> String {
        switch unit {
        case .gram: return "g"
        case .kilogram: return "kg"
        case .piece: return String(localized: "Stück", bundle: .module)
        }
    }

    /// "2,5 kg", "500 g", "3 Stück".
    static func amountText(_ item: StoredPantryItem) -> String {
        amountText(amount: item.amount, unit: item.unit)
    }

    static func amountText(amount: Double, unit: PantryUnit) -> String {
        // A thousand grams and more read as kilograms: "1,5 kg", not
        // "1.500 g", which looks like one and a half grams.
        if unit == .gram, amount >= 1_000 {
            return amountText(amount: amount / 1_000, unit: .kilogram)
        }
        return "\(number(amount)) \(unitTitle(unit))"
    }

    /// The number alone, with up to two decimals, in the app's language and
    /// without grouping: "1000", not "1.000", which `parse` would read as one.
    static func number(_ amount: Double) -> String {
        amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(AppSettings.locale))
    }

    /// A typed amount, with a comma or a point; nil when it is no number.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value >= 0 else { return nil }
        return value
    }
}

/// On a recipe's page: what of the recipe is in the pantry at the amount
/// shown, and what is missing. Shown only while the pantry has anything in
/// it; the reading is PantryMatcher in the package.
struct PantryCheckCard: View {
    let model: AppModel
    let recipe: RecipeExportData
    let scale: Double
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let pantry = model.availablePantry
        if !pantry.isEmpty {
            let check = PantryMatcher.check(recipe, scale: scale, pantry: pantry)
            if !check.needs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Vorrat")
                        .font(AppFont.headline)
                        .foregroundStyle(Palette.cardTitle(colorScheme))
                    if check.isComplete {
                        Label("Alle \(check.needs.count) Zutaten sind im Vorrat.", systemImage: "checkmark.circle")
                            .font(AppFont.subheadline)
                            .foregroundStyle(Palette.subtitle(colorScheme))
                    } else {
                        Text("\(check.covered.count) von \(check.needs.count) Zutaten im Vorrat")
                            .font(AppFont.subheadline)
                            .foregroundStyle(Palette.subtitle(colorScheme))
                        ForEach(check.missing, id: \.name) { need in
                            let amount = PantryMatcher.baseText(need.missingBase, counted: need.isCounted, locale: AppSettings.locale)
                            Text("Es fehlen \(amount) \(need.name)")
                                .font(AppFont.subheadline)
                                .foregroundStyle(Palette.warning(colorScheme))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }
}

/// "Eingekauft": the lines of a shopping list go into the pantry — but with
/// what was actually bought, not with what the recipe needs. Every line is
/// prefilled with the standard package and can be corrected before booking.
struct ShoppingListIntakeSheet: View {
    let model: AppModel
    let listID: String
    let onBooked: (AppModel.PantryIntakeResult) -> Void
    @State var lines: [Line]
    @Environment(\.dismiss) var dismiss

    struct Line: Identifiable {
        let id: String
        let item: StoredShoppingListItem
        /// The recipe's amount, for the small print.
        let needed: String
        var amount: String
        var unit: PantryUnit
    }

    init(model: AppModel, listID: String, items: [StoredShoppingListItem],
         onBooked: @escaping (AppModel.PantryIntakeResult) -> Void) {
        self.model = model
        self.listID = listID
        self.onBooked = onBooked
        _lines = State(initialValue: items.map { item in
            let bought = ShoppingListText.package(for: item) ?? ShoppingListText.need(for: item)
            return Line(id: item.id, item: item,
                        needed: ShoppingListText.neededText(item).trimmingCharacters(in: .whitespaces),
                        amount: PantryText.number(bought.amount), unit: bought.unit)
        })
    }

    private var hasAmount: Bool {
        lines.contains { (PantryText.parse($0.amount) ?? 0) > 0 }
    }

    var body: some View {
        Form {
            Section {
                ForEach($lines) { $line in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: line.item.name)
                            .font(AppFont.headline)
                        Text("Benötigt: \(line.needed)")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("Gekaufte Menge", text: $line.amount)
                                .frame(width: 96)
                                .foregroundStyle(PantryText.parse(line.amount) != nil ? Color.primary : Color.red)
                            Picker("Einheit", selection: $line.unit) {
                                ForEach(PantryUnit.allCases) { unit in
                                    Text(verbatim: PantryText.unitTitle(unit)).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                            // g ↔ kg keeps the quantity: 500 g become 0,5 kg,
                            // not 500 kg. Pieces have no conversion.
                            .onChange(of: line.unit) { old, new in
                                if let from = old.grams, let to = new.grams, let value = PantryText.parse(line.amount) {
                                    line.amount = PantryText.number(value * from / to)
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text("Vorgeschlagen sind übliche Gebindegrößen. Trage ein, was Du wirklich gekauft hast. Eine leere Menge lässt die Zeile auf der Liste.")
            }
        }
        .navigationTitle("Eingekauft")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Buchen") {
                    let booked = lines.map {
                        AppModel.PantryIntakeLine(item: $0.item, amount: PantryText.parse($0.amount) ?? 0, unit: $0.unit)
                    }
                    onBooked(model.receiveIntoPantry(booked, fromList: listID))
                    dismiss()
                }
                .disabled(!hasAmount)
            }
        }
    }
}
