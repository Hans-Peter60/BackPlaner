//
//  ShoppingCartsView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 12.01.22.
//

import BakePlannerCore
import SwiftUI
import CoreData
import os

struct ShoppingCartsView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)])
    private var shoppingCarts: FetchedResults<ShoppingCart>

    var gridItemLayout = [GridItem(scaledColumnSize(80), alignment: .trailing), GridItem(scaledColumnSize(80), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading)]

    var dateFormat:DateFormat = DateFormat()

    /// The list whose deletion is waiting to be confirmed. An `ShoppingCart?`
    /// rather than a Bool: with one flag for every row, the dialog that ends up
    /// being presented could delete a different list than the one tapped.
    @State private var cartPendingDeletion: ShoppingCart?
    /// "Eingekauft": the whole list goes into the pantry after a confirmation.
    @State private var cartPendingIntake: ShoppingCart?
    /// How many lines the last intake booked, for the message.
    @State private var intakeCount: Int?

    /// The shopping-list entry being edited, shown in a sheet.
    @State private var selectedIngredient: Ingredient?

    // "An Erinnerungen senden": the count afterwards, or the refusal.
    @State private var reminderCount = 0
    @State private var showingRemindersResult = false
    @State private var showingRemindersDenied = false
    
    var body: some View {
        Group {
            if shoppingCarts.isEmpty {
                ContentUnavailableView {
                    Label("Keine Einkaufslisten", systemImage: "cart")
                } description: {
                    Text("Öffne ein Rezept und wähle den Tab „Einkaufsliste“, um seine Zutaten auf eine Liste zu setzen.")
                } actions: {
                    NavigationLink("Eigene Rezepte öffnen") {
                        RecipeListView()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentTop)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    ForEach(shoppingCarts.sorted(by: { $0.date < $1.date }), id: \.self) { shoppingCart in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                // One localizable string, not a concatenation:
                                // "Einkaufsliste vom" stood in German in the
                                // English and French app.
                                Text("Einkaufsliste vom \(dateFormat.calculateDate(dT: shoppingCart.date))")
                                    .font(Theme.brandFont(20))
                                
                                Spacer()

                                // The list into Apple Reminders, which can be
                                // shared with the family. Icon only: with a
                                // title the header wrapped on an iPhone.
                                IconActionButton(systemImage: "checklist", style: .neutral, accessibilityLabel: "Einkaufsliste an Erinnerungen senden", controlSize: .regular) {
                                    sendToReminders(shoppingCart)
                                }
                                .accessibilityIdentifier("shopping.reminders")

                                // Everything bought: every line into the pantry,
                                // the list is done with. Pro, like the pantry.
                                if Entitlements.shared.isUnlocked(.pantry), !shoppingCart.ingredientsArray.isEmpty {
                                    IconActionButton(systemImage: "shippingbox", style: .primary, accessibilityLabel: "Eingekauft – alles in den Vorrat", controlSize: .regular) {
                                        cartPendingIntake = shoppingCart
                                    }
                                    .accessibilityIdentifier("shopping.receiveAll")
                                }

                                // Icon only, like its neighbours: with a title the
                                // row wrapped on an iPhone once the pantry button came.
                                IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Einkaufsliste löschen", controlSize: .regular) {
                                    cartPendingDeletion = shoppingCart
                                }
                                .padding(.trailing)
                            }
                            
                            let recipes = (shoppingCart.recipes as? Set<Recipe> ?? []).sorted { $0.name < $1.name }
                            // Recipes from the cloud have no Core Data object,
                            // so their names are listed from the stored names.
                            let recipeNames = recipes.map(\.name) + shoppingCart.cloudRecipeNamesArray
                            if !recipeNames.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(recipeNames.sorted(), id: \.self) { recipeName in
                                        Text("- " + recipeName)
                                            .font(Theme.brandFont(16))
                                    }
                                }
                                .padding(.bottom, 2)
                            }
                            
                            if shoppingCart.ingredientsArray.isEmpty {
                                Text("Noch keine Zutaten")
                                    .font(Theme.bodyFont(15))
                                    .foregroundColor(Theme.subtitle)
                            } else {
                                // Grouped by shelf, in the order of a walk
                                // through the shop; see ShoppingListCategory.
                                ForEach(ShoppingListCategory.shelves(shoppingCart.ingredientsArray, name: \.name)) { shelf in
                                    Label(shelf.category.title, systemImage: shelf.category.systemImage)
                                        .font(Theme.brandFont(15))
                                        .foregroundColor(Theme.subtitle)
                                        .padding(.top, 6)
                                        .accessibilityAddTraits(.isHeader)

                                    ForEach(shelf.items) { ingredient in
                                        ShoppingCartIngredientRow(
                                            ingredient: ingredient,
                                            onEdit: { selectedIngredient = ingredient },
                                            onRemove: { remove(ingredient) },
                                            onReceive: Entitlements.shared.isUnlocked(.pantry) ? { receive(ingredient) } : nil
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 10)
                        
                        Divider()
                    }
                }
                .padding(.leading)
            }
        }
        .warmBackground()
        .navigationTitle("Einkaufslisten")
        .sheet(item: $selectedIngredient) { ingredient in
            EditShoppingCartIngredientView(ingredient: ingredient)
                .environment(\.managedObjectContext, viewContext)
        }
        // Attached once, outside the loop: the dialog belongs to the list that
        // was tapped, not to whichever row SwiftUI happens to present.
        .confirmationDialog(
            "Bist Du sicher?",
            isPresented: Binding(
                get: { cartPendingDeletion != nil },
                set: { if !$0 { cartPendingDeletion = nil } }
            ),
            presenting: cartPendingDeletion
        ) { shoppingCart in
            Button("Ja, löschen", role: .destructive) {
                delete(shoppingCart)
            }
            Button("Nein", role: .cancel) { }
        }
        // An alert, not a confirmation dialog: the dialog came up as a
        // popover anchored to the scroll view, without its cancel button.
        .alert(
            "Alles eingekauft?",
            isPresented: Binding(
                get: { cartPendingIntake != nil },
                set: { if !$0 { cartPendingIntake = nil } }
            ),
            presenting: cartPendingIntake
        ) { shoppingCart in
            Button("In den Vorrat buchen und Liste löschen") {
                receiveAll(shoppingCart)
            }
            Button("Abbrechen", role: .cancel) { }
        } message: { shoppingCart in
            Text("\(shoppingCart.ingredientsArray.count) Zeilen werden auf die Posten gleichen Namens gebucht oder als neue Posten angelegt.")
        }
        .alert("In den Vorrat gebucht", isPresented: Binding(
            get: { intakeCount != nil },
            set: { if !$0 { intakeCount = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(intakeCount ?? 0) Zeilen sind im Vorrat. Die Einkaufsliste ist erledigt.")
        }
        .alert("An Erinnerungen gesendet", isPresented: $showingRemindersResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(reminderCount) Einträge in der Liste „BakePlanner“ angelegt.")
        }
        .alert("Kein Zugriff auf Erinnerungen", isPresented: $showingRemindersDenied) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("BakePlanner darf keine Erinnerungen anlegen. Das lässt sich in den iOS-Einstellungen unter BakePlanner ändern.")
        }
    }

    /// Every item of the list as an open reminder, worded as the row shows it.
    private func sendToReminders(_ shoppingCart: ShoppingCart) {
        let items = shoppingCart.ingredientsArray.map { ingredient in
            Rational.getPortion(unit: ingredient.unit ?? "", weight: ingredient.weight,
                                num: ingredient.num, denom: ingredient.denom, targetServings: 2) + ingredient.name
        }
        guard !items.isEmpty else { return }
        Task { @MainActor in
            do {
                reminderCount = try await RemindersExport.send(items)
                showingRemindersResult = true
            } catch {
                showingRemindersDenied = true
            }
        }
    }

    private func delete(_ shoppingCart: ShoppingCart) {
        withAnimation {
            viewContext.delete(shoppingCart)
            save("Einkaufsliste konnte nicht gelöscht werden")
        }
    }

    /// Takes a single entry off the list. The ingredient belongs to this
    /// shopping list alone — it is a copy made when the recipe was added — so
    /// deleting it leaves the recipe untouched.
    /// Bought: the line goes into the pantry — onto the item of the same
    /// name, or as a new one — and off the list.
    private func receive(_ ingredient: Ingredient) {
        let intake = Pantry.intake(unit: ingredient.unit, weight: ingredient.weight, normWeight: ingredient.normWeight,
                                   num: ingredient.num, denom: ingredient.denom)
        do {
            try CoreDataPantryStore(context: viewContext).receive(name: ingredient.name, amount: intake.amount, unit: intake.unit)
        } catch {
            AppLog.persistence.error("Taking a shopping-list line into the pantry failed: \(error)")
            return
        }
        remove(ingredient)
    }

    /// Everything on the list is bought: every line into the pantry, then
    /// the list goes. Lines that cannot be booked stay on the list, so
    /// nothing is lost silently.
    private func receiveAll(_ shoppingCart: ShoppingCart) {
        let store = CoreDataPantryStore(context: viewContext)
        var booked = 0
        var failed: [Ingredient] = []
        for ingredient in shoppingCart.ingredientsArray {
            let intake = Pantry.intake(unit: ingredient.unit, weight: ingredient.weight, normWeight: ingredient.normWeight,
                                       num: ingredient.num, denom: ingredient.denom)
            do {
                try store.receive(name: ingredient.name, amount: intake.amount, unit: intake.unit)
                booked += 1
            } catch {
                AppLog.persistence.error("Taking a shopping-list line into the pantry failed: \(error)")
                failed.append(ingredient)
            }
        }
        withAnimation {
            if failed.isEmpty {
                viewContext.delete(shoppingCart)
            } else {
                for ingredient in shoppingCart.ingredientsArray where !failed.contains(ingredient) {
                    viewContext.delete(ingredient)
                }
            }
            save("Einkaufsliste konnte nicht in den Vorrat gebucht werden")
        }
        intakeCount = booked
    }

    private func remove(_ ingredient: Ingredient) {
        withAnimation {
            viewContext.delete(ingredient)
            save("Zutat konnte nicht entfernt werden")
        }
    }

    private func save(_ message: String) {
        do {
            try viewContext.save()
        } catch {
            AppLog.shoppingCart.error("\(message): \(error)")
        }
    }
}

/// One line of a shopping list.
///
/// Its own view with an `@ObservedObject`: as a plain `Text` inside the loop
/// the row was built from a value SwiftUI does not watch, so a changed amount
/// only showed up after leaving and reopening the screen.
private struct ShoppingCartIngredientRow: View {

    @ObservedObject var ingredient: Ingredient

    var onEdit: () -> Void
    var onRemove: () -> Void
    /// Nil while the pantry is locked.
    var onReceive: (() -> Void)?

    var body: some View {
        HStack {
            Text("• " + Rational.getPortion(unit: ingredient.unit ?? "", weight: ingredient.weight, num: ingredient.num, denom: ingredient.denom, targetServings: 2) + ingredient.name)
                .font(Theme.bodyFont(15))
                .onTapGesture { onEdit() }
                // A tap gesture alone carries no semantics: without the button
                // trait VoiceOver announces the row as plain text and never
                // offers to activate it.
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Menge ändern")

            Spacer()

            if let onReceive {
                IconActionButton(systemImage: "shippingbox", style: .primary, accessibilityLabel: "In den Vorrat übernehmen", controlSize: .small) {
                    onReceive()
                }
                .accessibilityIdentifier("shoppingList.receive")
            }
            IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Zutat von der Einkaufsliste entfernen", controlSize: .small) {
                onRemove()
            }
            .padding(.trailing)
        }
    }
}

/// Changes the amount of one shopping-list entry.
///
/// The name is deliberately not editable: entries of the same name are merged
/// when a further recipe is put on the list, so renaming one would silently
/// split it off from its own group.
struct EditShoppingCartIngredientView: View {

    @ObservedObject var ingredient: Ingredient

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var weight: Double
    @State private var unit: String
    @State private var num: Int
    @State private var denom: Int

    private let calcWeight = CalcIngredientWeight()

    init(ingredient: Ingredient) {
        self.ingredient = ingredient
        _weight = State(initialValue: ingredient.weight)
        _unit   = State(initialValue: ingredient.unit ?? "")
        _num    = State(initialValue: ingredient.num)
        _denom  = State(initialValue: ingredient.denom)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Zutat", value: ingredient.name)

                    HStack {
                        Text("Menge")
                        Spacer()
                        NumberField("", value: $weight)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: scaledLayoutValue(80))
                            .accessibilityLabel("Menge")
                    }

                    UnitSelectionView(unit: $unit)
                } footer: {
                    Text("Die Menge gilt für diese Einkaufsliste. Das Rezept bleibt unverändert.")
                }

                Section {
                    HStack {
                        Text("Bruch")
                        Spacer()
                        NumberField("", value: $num)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: scaledLayoutValue(44))
                            .accessibilityLabel("Zähler")
                        Text(verbatim: "/")
                            .accessibilityHidden(true)
                        NumberField("", value: $denom)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: scaledLayoutValue(44))
                            .accessibilityLabel("Nenner")
                    }
                } footer: {
                    Text("Für Angaben wie ½ Würfel Hefe. Leer lassen, wenn Du mit der Menge oben arbeitest.")
                }

                Section {
                    Button("Zutat entfernen", role: .destructive) {
                        viewContext.delete(ingredient)
                        try? viewContext.save()
                        dismiss()
                    }
                }
            }
            .clearScrollBackground()
            .warmBackground()
            .navigationTitle(Text("Menge ändern"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { apply() }
                }
            }
        }
    }

    private func apply() {
        ingredient.weight = weight
        ingredient.unit   = unit
        ingredient.num    = num
        ingredient.denom  = denom
        // Kept in step with the amount: the normalised weight is what decides
        // how entries are merged and converted when another recipe is added.
        ingredient.normWeight = calcWeight.calcIngredientWeight(
            weight: weight,
            unit: unit,
            name: ingredient.name,
            num: num,
            denom: denom
        )

        do {
            try viewContext.save()
        } catch {
            AppLog.shoppingCart.error("Menge konnte nicht gespeichert werden: \(error)")
        }

        dismiss()
    }
}
