//
//  ShoppingCardSelectFormView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 13.01.22.
//

import SwiftUI
import CoreData
import os

struct ShoppingCartSelectFormView: View {

    @Environment(\.presentationMode) var presentationMode
    @Environment(\.managedObjectContext) var viewContext

    var recipe: Recipe

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)])
    private var shoppingCarts: FetchedResults<ShoppingCart>

    @EnvironmentObject var model: RecipeModel

    private enum ShoppingCartMode: Int {
        case newList
        case existingList
    }

    private var sortedShoppingCarts: [ShoppingCart] {
        shoppingCarts.sorted { $0.date < $1.date }
    }

    private let dateFormat = DateFormat()
    private let dateRange: ClosedRange<Date> = {
        let calendar = Calendar.current
        let startComponents = DateComponents(year: GlobalVariables.year, month: GlobalVariables.month, day: GlobalVariables.day)
        let endComponents = DateComponents(year: (GlobalVariables.year ?? calendar.component(.year, from: Date())) + 1, month: GlobalVariables.month, day: GlobalVariables.day)
        let startDate = calendar.date(from:startComponents) ?? Date()
        let endDate = calendar.date(from:endComponents) ?? calendar.date(byAdding: .year, value: 1, to: startDate) ?? startDate
        return startDate ... endDate
    }()

    @State private var date = Date()
    @State private var mode = ShoppingCartMode.newList
    @State private var unitSetSc = UnitSetFB()
    @State private var unitSetNew = UnitSetFB()
    @State private var showingAlert = false
    @State private var confirmationShown = false
    @State private var createdShoppingCart = false

    var body: some View {
        Form {
            Section("Einkaufsliste") {
                Picker("Ziel", selection: $mode) {
                    Text("Neue Liste").tag(ShoppingCartMode.newList)
                    Text("Bestehende Liste").tag(ShoppingCartMode.existingList)
                }
                .pickerStyle(.segmented)

                if mode == .newList {
                    DatePicker(
                        "Datum",
                        selection: $date,
                        in: dateRange,
                        displayedComponents: [.date]
                    )
                    .environment(\.locale, AppSettings.locale)

                    IconActionButton(systemImage: "cart.badge.plus", style: .primary, accessibilityLabel: "Einkaufsliste erstellen", title: "Erstellen", controlSize: .regular) {
                        createShoppingCart()
                    }
                }
            }

            if mode == .existingList {
                Section("Bestehende Einkaufslisten") {
                    if sortedShoppingCarts.isEmpty {
                        ContentUnavailableView(
                            "Keine Einkaufsliste vorhanden",
                            systemImage: "cart",
                            description: Text("Erstelle zuerst eine neue Liste.")
                        )
                    } else {
                        ForEach(sortedShoppingCarts, id: \.self) { shoppingCart in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Einkaufsliste vom " + dateFormat.calculateDate(dT: shoppingCart.date))
                                        .font(Theme.brandFont(16))
                                    Text("\(shoppingCart.ingredientsArray.count) Zutaten")
                                        .font(Theme.bodyFont(13))
                                        .foregroundColor(Theme.subtitle)
                                }

                                Spacer()

                                IconActionButton(systemImage: "plus", style: .primary, accessibilityLabel: "Rezept zur Einkaufsliste hinzufügen", controlSize: .regular) {
                                    addRecipe(to: shoppingCart)
                                }
                            }
                            .swipeActions(allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    confirmationShown = true
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            .confirmationDialog("Bist Du sicher?", isPresented: $confirmationShown) {
                                Button("Ja, löschen") {
                                    withAnimation {
                                        viewContext.delete(shoppingCart)
                                        do {
                                            try viewContext.save()
                                        } catch {
                                            AppLog.shoppingCart.error("Einkaufsliste konnte nicht gelöscht werden: \(error)")
                                        }
                                    }
                                }
                                .keyboardShortcut(.defaultAction)

                                Button("Nein", role: .cancel) {}
                            }
                        }
                    }
                }
            }

            if createdShoppingCart {
                Section {
                    NavigationLink("Einkaufslisten anzeigen", destination: ShoppingCartsView())
                }
            }
        }
        .alert("Zutaten wurden auf die Einkaufsliste gesetzt", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        }
        .navigationTitle(Text("Einkaufsliste erstellen"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func createShoppingCart() {
        let calendar = Calendar.current
        let shoppingCart: ShoppingCart

        if let existingShoppingCart = shoppingCarts.first(where: {
            calendar.isDate($0.date, inSameDayAs: date)
        }) {
            shoppingCart = existingShoppingCart
        } else {
            let newShoppingCart = ShoppingCart(context: viewContext)
            newShoppingCart.id = UUID()
            newShoppingCart.date = date
            shoppingCart = newShoppingCart
        }

        if addRecipe(to: shoppingCart) {
            createdShoppingCart = true
            mode = .existingList
        }
    }

    @discardableResult
    private func addRecipe(to shoppingCart: ShoppingCart) -> Bool {
        showingAlert = false
        harmonizeIngredients(in: shoppingCart)
        shoppingCart.addToRecipes(recipe)

        for component in recipe.componentsArray {
            for ingredient in component.ingredientsArray where shouldAddToShoppingCart(ingredient) {
                merge(ingredient, into: shoppingCart)
            }
        }

        do {
            try viewContext.save()
            showingAlert = true
            return true
        } catch {
            AppLog.shoppingCart.error("Einkaufsliste konnte nicht gespeichert werden: \(error)")
            return false
        }
    }

    private func harmonizeIngredients(in shoppingCart: ShoppingCart) {
        var canonicalIngredients: [String: Ingredient] = [:]

        for ingredient in shoppingCart.ingredientsArray {
            let normalizedName = IngredientNameNormalizer.displayName(ingredient.name)
            let normalizedUnit = (ingredient.unit ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedLowercase
            let key = IngredientNameNormalizer.comparisonKey(normalizedName) + "|" + normalizedUnit

            ingredient.name = normalizedName

            if let canonicalIngredient = canonicalIngredients[key] {
                canonicalIngredient.weight += ingredient.weight
                canonicalIngredient.normWeight += ingredient.normWeight
                addFractions(from: ingredient, to: canonicalIngredient)
                viewContext.delete(ingredient)
            } else {
                canonicalIngredients[key] = ingredient
            }
        }
    }

    private func shouldAddToShoppingCart(_ ingredient: Ingredient) -> Bool {
        let ignoredIngredientNames = ["Wasser", "Salz", "Anstellgut", "Sauerteig"]
        let hasIgnoredName = ignoredIngredientNames.contains { ingredient.name.contains($0) }
        let hasUnit = !(ingredient.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return !hasIgnoredName && ingredient.normWeight > 0 && hasUnit
    }

    private func merge(_ ingredient: Ingredient, into shoppingCart: ShoppingCart) {
        let ingredientName = IngredientNameNormalizer.displayName(ingredient.name)
        let comparisonKey = IngredientNameNormalizer.comparisonKey(ingredient.name)

        guard let existing = shoppingCart.ingredientsArray.first(where: {
            IngredientNameNormalizer.comparisonKey($0.name) == comparisonKey
        }) else {
            addNewShoppingCartIngredient(
                from: ingredient,
                normalizedName: ingredientName,
                to: shoppingCart
            )
            return
        }

        existing.name = ingredientName

        if existing.unit == ingredient.unit {
            existing.weight += ingredient.weight
            existing.normWeight += ingredient.normWeight
            addFractions(from: ingredient, to: existing)
        } else {
            mergeWithUnitConversion(ingredient, into: existing)
        }
    }

    private func addNewShoppingCartIngredient(
        from ingredient: Ingredient,
        normalizedName: String,
        to shoppingCart: ShoppingCart
    ) {
        let newIngredient = Ingredient(context: viewContext)
        newIngredient.id = UUID()
        newIngredient.name = normalizedName
        newIngredient.unit = ingredient.unit
        newIngredient.weight = ingredient.weight
        newIngredient.num = ingredient.num
        newIngredient.denom = ingredient.denom
        newIngredient.normWeight = ingredient.normWeight
        newIngredient.number = 0

        shoppingCart.addToIngredients(newIngredient)
    }

    private func addFractions(from ingredient: Ingredient, to existing: Ingredient) {
        guard existing.denom != 0, ingredient.denom != 0 else { return }
        guard existing.num != 0 || ingredient.num != 0 else { return }

        let num = (existing.num * ingredient.denom) + (ingredient.num * existing.denom)
        let denom = existing.denom * ingredient.denom
        let gcd = Rational.greatestCommonDivisor(num, denom)

        guard gcd != 0 else { return }
        existing.num = num / gcd
        existing.denom = denom / gcd
    }

    private func mergeWithUnitConversion(_ ingredient: Ingredient, into existing: Ingredient) {
        unitSetSc = UnitSetFB()
        unitSetNew = UnitSetFB()

        guard let existingUnit = existing.unit, !existingUnit.isEmpty else { return }
        guard let newUnit = ingredient.unit, !newUnit.isEmpty else { return }

        for unitSet in GlobalVariables.unitSets {
            if newUnit.localizedLowercase.contains(unitSet.name) || newUnit == unitSet.abbreviation {
                unitSetNew = unitSet
            }
            if existingUnit.localizedLowercase.contains(unitSet.name) || existingUnit == unitSet.abbreviation {
                unitSetSc = unitSet
            }
        }

        guard !unitSetSc.baseUnit.isEmpty, unitSetSc.baseUnit == unitSetNew.baseUnit else { return }

        existing.weight += ingredient.weight / unitSetSc.factor * unitSetNew.factor
        existing.normWeight += ingredient.normWeight / unitSetSc.factor * unitSetNew.factor
        addConvertedFractions(from: ingredient, to: existing)
    }

    private func addConvertedFractions(from ingredient: Ingredient, to existing: Ingredient) {
        guard existing.denom != 0, ingredient.denom != 0 else { return }
        guard existing.num != 0 || ingredient.num != 0 else { return }

        let num = Int((Double(existing.num * ingredient.denom) * unitSetSc.factor) + (Double(ingredient.num * existing.denom) * unitSetNew.factor))
        let denom = existing.denom * ingredient.denom
        let gcd = Rational.greatestCommonDivisor(num, denom)

        guard gcd != 0 else { return }
        existing.num = num / gcd
        existing.denom = denom / gcd
    }
}
