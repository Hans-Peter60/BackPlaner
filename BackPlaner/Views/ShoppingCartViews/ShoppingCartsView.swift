//
//  ShoppingCartsView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 12.01.22.
//

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

    /// The shopping-list entry being edited, shown in a sheet.
    @State private var selectedIngredient: Ingredient?
    
    var body: some View {
        Group {
            if shoppingCarts.isEmpty {
                ContentUnavailableView(
                    "Keine Einkaufslisten",
                    systemImage: "cart",
                    description: Text("Erstelle eine Einkaufsliste direkt aus einem Rezept.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    ForEach(shoppingCarts.sorted(by: { $0.date < $1.date }), id: \.self) { shoppingCart in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Einkaufsliste vom " + dateFormat.calculateDate(dT: shoppingCart.date))
                                    .font(Theme.brandFont(20))
                                
                                Spacer()
                                
                                IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Einkaufsliste löschen", title: "Löschen", controlSize: .regular) {
                                    cartPendingDeletion = shoppingCart
                                }
                                .padding(.trailing)
                            }
                            
                            let recipes = (shoppingCart.recipes as? Set<Recipe> ?? []).sorted { $0.name < $1.name }
                            if !recipes.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(recipes) { recipe in
                                        Text("- " + recipe.name)
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
                                ForEach(shoppingCart.ingredientsArray.sorted(by: { $0.name < $1.name })) { ingredient in
                                    HStack {
                                        Text("• " + Rational.getPortion(unit:ingredient.unit ?? "", weight:ingredient.weight, num:ingredient.num, denom:ingredient.denom, targetServings: 2) + ingredient.name)
                                            .font(Theme.bodyFont(15))
                                            .onTapGesture {
                                                selectedIngredient = ingredient
                                            }
                                            // A tap gesture alone carries no semantics: without the
                                            // button trait VoiceOver announces the row as plain text
                                            // and never offers to activate it.
                                            .accessibilityAddTraits(.isButton)
                                            .accessibilityHint("Menge ändern")

                                        Spacer()

                                        IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Zutat von der Einkaufsliste entfernen", controlSize: .small) {
                                            remove(ingredient)
                                        }
                                        .padding(.trailing)
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
                        TextField("", value: $weight, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
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
                        TextField("", value: $num, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: scaledLayoutValue(44))
                            .accessibilityLabel("Zähler")
                        Text(verbatim: "/")
                            .accessibilityHidden(true)
                        TextField("", value: $denom, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
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
