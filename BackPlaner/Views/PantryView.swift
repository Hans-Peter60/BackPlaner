//
//  PantryView.swift
//  BackPlaner
//
//  "Vorrat" from the recipe list's "Mehr" menu: what is in the house, by
//  shelf like the shopping list, each with its amount and how long it
//  keeps. A tap edits, "+" adds, a swipe removes. The logic — shelf life,
//  suggested names, taking in a bought line — is Pantry in the package;
//  the items come and go through CoreDataPantryStore.
//

import BakePlannerCore
import CoreData
import SwiftUI

struct PantryView: View {

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var managedItems: FetchedResults<PantryItem>

    /// The item being edited, or a blank one for "+".
    @State private var editing: PantryEditing?

    private var store: CoreDataPantryStore { CoreDataPantryStore(context: viewContext) }

    private var items: [StoredPantryItem] {
        managedItems.map(CoreDataPantryStore.stored).sorted(by: CoreDataPantryStore.ordered)
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Noch nichts im Vorrat", systemImage: "shippingbox")
                } description: {
                    Text("Lege Mehle, Saaten und Hefe mit Menge und Mindesthaltbarkeit an. Aus der Einkaufsliste wandert Gekauftes mit einem Tipp hierher.")
                } actions: {
                    Button("Posten hinzufügen") { beginAdding() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accentText)
                }
            } else {
                List {
                    let attention = Pantry.needingAttention(items)
                    if !attention.isEmpty {
                        Section {
                            ForEach(attention) { item in
                                row(item)
                            }
                        } header: {
                            Label("Bald aufbrauchen", systemImage: "exclamationmark.triangle")
                        }
                    }
                    ForEach(ShoppingListCategory.shelves(items, name: \.name)) { shelf in
                        Section {
                            ForEach(shelf.items) { item in
                                row(item)
                            }
                        } header: {
                            Label(shelf.category.title, systemImage: shelf.category.systemImage)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .warmBackground()
        .navigationTitle("Vorrat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Posten hinzufügen", systemImage: "plus") { beginAdding() }
                    .accessibilityIdentifier("pantry.add")
            }
        }
        .sheet(item: $editing) { editing in
            NavigationStack {
                PantryItemEditorView(item: editing.item, store: store)
            }
        }
    }

    private func beginAdding() {
        editing = PantryEditing(item: nil)
    }

    private func row(_ item: StoredPantryItem) -> some View {
        Button {
            editing = PantryEditing(item: item)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(Theme.brandFont(16))
                        .foregroundColor(Theme.cardTitle)
                    if let line = shelfLifeText(item) {
                        line
                            .font(Theme.bodyFont(12))
                    }
                    if !item.note.isEmpty {
                        Text(item.note)
                            .font(Theme.bodyFont(12))
                            .foregroundColor(Theme.subtitle)
                    }
                }
                Spacer()
                Text(PantryItemEditorView.amountText(item))
                    .font(Theme.bodyFont(15))
                    .foregroundColor(Theme.subtitle)
            }
            // The whole row takes the tap, not only its texts.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                try? store.delete(id: item.id)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pantry.item")
    }

    /// "Haltbar bis 20.11.2026", coloured when it is soon or over.
    private func shelfLifeText(_ item: StoredPantryItem) -> Text? {
        guard let bestBefore = item.bestBefore else { return nil }
        let date = bestBefore.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(AppSettings.locale))
        switch PantryShelfLife.of(bestBefore) {
        case .unknown:
            return nil
        case .fresh:
            return Text("Haltbar bis \(date)").foregroundColor(Theme.subtitle)
        case .soon(let days) where days == 0:
            return Text("Läuft heute ab").foregroundColor(.orange)
        case .soon(let days):
            return Text("Läuft in \(days) Tagen ab (\(date))").foregroundColor(.orange)
        case .expired(let days):
            return Text("Seit \(days) Tagen abgelaufen (\(date))").foregroundColor(Theme.danger)
        }
    }
}

/// What the editor sheet opens with: an item, or nothing for a new one.
private struct PantryEditing: Identifiable {
    let item: StoredPantryItem?
    var id: String { item?.id ?? "new" }
}

/// One pantry item: name with suggestions from the recipes, amount and
/// unit, the best-before date, a note.
struct PantryItemEditorView: View {

    let item: StoredPantryItem?
    let store: CoreDataPantryStore

    @Environment(\.dismiss) private var dismiss

    /// The recipes, for the names they use; read in the body so the fetch
    /// is filled before the suggestions are worked out.
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>
    /// The names of the recipes' bought ingredients, most used first.
    @State private var suggestions: [String] = []

    @State private var name: String
    @State private var amount: Double
    @State private var unit: PantryUnit
    @State private var hasBestBefore: Bool
    @State private var bestBefore: Date
    @State private var note: String
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    init(item: StoredPantryItem?, store: CoreDataPantryStore) {
        self.item = item
        self.store = store
        _name = State(initialValue: item?.name ?? "")
        _amount = State(initialValue: item?.amount ?? 1_000)
        _unit = State(initialValue: item?.unit ?? .gram)
        _hasBestBefore = State(initialValue: item?.bestBefore != nil)
        _bestBefore = State(initialValue: item?.bestBefore ?? Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date())
        _note = State(initialValue: item?.note ?? "")
    }

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("pantry.name")
                // Names from the recipes, so the pantry and the recipes
                // agree on what "Weizenmehl 550" is called.
                let matching = Array(Pantry.matchingNames(name, in: suggestions).prefix(6))
                if nameFocused || item == nil, !matching.isEmpty {
                    ForEach(matching, id: \.self) { suggestion in
                        Button {
                            name = suggestion
                            nameFocused = false
                        } label: {
                            Label(suggestion, systemImage: "arrow.turn.down.left")
                                .font(Theme.bodyFont(14))
                        }
                        .accessibilityIdentifier("pantry.suggestion")
                    }
                }
            } header: {
                Text("Zutat")
            } footer: {
                if item == nil && !suggestions.isEmpty {
                    Text("Vorschläge aus Deinen Rezepten")
                }
            }
            Section("Menge") {
                HStack {
                    NumberField("Menge", value: $amount)
                        .accessibilityIdentifier("pantry.amount")
                    Picker("Einheit", selection: $unit) {
                        ForEach(PantryUnit.allCases) { unit in
                            Text(Self.unitTitle(unit)).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
            }
            Section {
                Toggle("Mindesthaltbarkeit", isOn: $hasBestBefore)
                if hasBestBefore {
                    DatePicker("Haltbar bis", selection: $bestBefore, displayedComponents: .date)
                }
            }
            Section("Notiz") {
                TextField("Mühle, Sorte, angebrochen …", text: $note, axis: .vertical)
            }
            if item != nil {
                Section {
                    Button("Aus dem Vorrat entfernen", role: .destructive) {
                        if let item { try? store.delete(id: item.id) }
                        dismiss()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .warmBackground()
        // Short titles: "Posten bearbeiten" was cut to "Posten bearbei…"
        // between "Abbrechen" and "Sichern" on an iPhone.
        .navigationTitle(item == nil ? "Neuer Posten" : "Posten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { save() }
                    .disabled(cleanName.isEmpty)
                    .accessibilityIdentifier("pantry.save")
            }
            // The number pad has no return key; this puts it away so the
            // date row below comes back into view.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .task {
            suggestions = Pantry.suggestedNames(from: recipes.map { RecipeExportData(recipe: $0, includingImage: false) })
        }
        .alert("Sichern fehlgeschlagen", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear { if item == nil { nameFocused = true } }
    }

    private func save() {
        do {
            if var existing = item {
                existing.name = cleanName
                existing.amount = amount
                existing.unit = unit
                existing.bestBefore = hasBestBefore ? bestBefore : nil
                existing.note = note
                try store.update(existing)
            } else {
                _ = try store.add(name: cleanName, amount: amount, unit: unit,
                                  bestBefore: hasBestBefore ? bestBefore : nil, note: note)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func unitTitle(_ unit: PantryUnit) -> String {
        switch unit {
        case .gram: return "g"
        case .kilogram: return "kg"
        case .piece: return String(localized: "Stück", locale: AppSettings.locale)
        }
    }

    /// "2,5 kg", "500 g", "3 Stück".
    static func amountText(_ item: StoredPantryItem) -> String {
        let number = item.amount.formatted(.number.precision(.fractionLength(0...2)).locale(AppSettings.locale))
        return "\(number) \(unitTitle(item.unit))"
    }
}
