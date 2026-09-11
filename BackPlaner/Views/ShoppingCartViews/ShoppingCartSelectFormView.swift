//
//  ShoppingCardSelectFormView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 13.01.22.
//

import SwiftUI
import CoreData
import os

/// One ingredient on its way to a shopping list, independent of where it came
/// from — a recipe on the device or one from the cloud, which has no Core Data
/// object at all.
struct ShoppingCartEntry {
    var name: String
    var unit: String
    var weight: Double
    var num: Int
    var denom: Int
}

/// What is being put on the list.
enum ShoppingCartSource {
    case localRecipe(Recipe)
    case cloudRecipe(RecipeFB)

    var name: String {
        switch self {
        case .localRecipe(let recipe): return recipe.name
        case .cloudRecipe(let recipe): return recipe.name
        }
    }

    var entries: [ShoppingCartEntry] {
        switch self {
        case .localRecipe(let recipe):
            return recipe.componentsArray.flatMap(\.ingredientsArray).map { ingredient in
                ShoppingCartEntry(
                    name: ingredient.name,
                    unit: ingredient.unit ?? "",
                    weight: ingredient.weight,
                    num: ingredient.num,
                    denom: ingredient.denom
                )
            }
        case .cloudRecipe(let recipe):
            return recipe.components.flatMap(\.ingredients).map { ingredient in
                ShoppingCartEntry(
                    name: ingredient.name,
                    unit: ingredient.unit,
                    weight: ingredient.weight,
                    num: ingredient.num,
                    denom: ingredient.denom
                )
            }
        }
    }
}

struct ShoppingCartSelectFormView: View {

    @Environment(\.presentationMode) var presentationMode
    @Environment(\.managedObjectContext) var viewContext

    var source: ShoppingCartSource

    init(recipe: Recipe) {
        self.source = .localRecipe(recipe)
    }

    init(recipeFB: RecipeFB) {
        self.source = .cloudRecipe(recipeFB)
    }

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
    private let calcWeight = CalcIngredientWeight()
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
    @State private var showingNoIngredientsAlert = false
    @State private var createdShoppingCart = false
    /// The list whose deletion is waiting to be confirmed — an object, not a
    /// flag: one flag shared by every row lets the dialog delete a list other
    /// than the one that was swiped.
    @State private var cartPendingDeletion: ShoppingCart?

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
                                    cartPendingDeletion = shoppingCart
                                } label: {
                                    // A swipe action reached by VoiceOver's actions
                                    // rotor needs a name; the icon alone gives none.
                                    Label("Einkaufsliste löschen", systemImage: "trash")
                                }
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
        // The one recipe tab that stood out as grey: a Form draws its own
        // system background, so it needs both of these to let the warm
        // gradient through, exactly as ShoppingCartsView does.
        .clearScrollBackground()
        .warmBackground()
        .alert("Zutaten wurden auf die Einkaufsliste gesetzt", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        }
        .alert("Keine Zutaten vorhanden", isPresented: $showingNoIngredientsAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Für dieses Rezept sind keine Zutaten hinterlegt, die auf eine Einkaufsliste passen.")
        }
        // Attached once, outside the loop, so the dialog belongs to the list
        // that was actually swiped.
        .confirmationDialog(
            "Bist Du sicher?",
            isPresented: Binding(
                get: { cartPendingDeletion != nil },
                set: { if !$0 { cartPendingDeletion = nil } }
            ),
            presenting: cartPendingDeletion
        ) { shoppingCart in
            Button("Ja, löschen", role: .destructive) {
                withAnimation {
                    viewContext.delete(shoppingCart)
                    do {
                        try viewContext.save()
                    } catch {
                        AppLog.shoppingCart.error("Einkaufsliste konnte nicht gelöscht werden: \(error)")
                    }
                }
            }
            Button("Nein", role: .cancel) { }
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

        // Amounts are converted for shopping BEFORE anything is merged, so
        // eggs from one recipe and eggs from another meet as pieces.
        let entries = source.entries
            .filter { shouldAddToShoppingCart($0) }
            .map { shoppingListEntry(from: $0) }

        guard !entries.isEmpty else {
            showingNoIngredientsAlert = true
            return false
        }

        harmonizeIngredients(in: shoppingCart)

        switch source {
        case .localRecipe(let recipe):
            shoppingCart.addToRecipes(recipe)
        case .cloudRecipe(let recipe):
            // A cloud recipe has no Core Data object to relate to, so only its
            // name is recorded — enough to see where the ingredients came from.
            shoppingCart.addCloudRecipeName(recipe.name)
        }

        for entry in entries {
            merge(entry, into: shoppingCart)
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

    /// Converts a recipe amount into the amount to buy — eggs by the piece
    /// instead of by weight, see ``ShoppingListAmount``.
    private func shoppingListEntry(from entry: ShoppingCartEntry) -> ShoppingCartEntry {
        let amount = ShoppingListAmount.forShoppingList(
            name: entry.name,
            unit: entry.unit,
            weight: entry.weight,
            num: entry.num,
            denom: entry.denom
        )

        return ShoppingCartEntry(
            name: entry.name,
            unit: amount.unit,
            weight: amount.weight,
            num: amount.num,
            denom: amount.denom
        )
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

    private func shouldAddToShoppingCart(_ entry: ShoppingCartEntry) -> Bool {
        let ignoredIngredientNames = ["Wasser", "Salz", "Anstellgut", "Sauerteig"]
        let hasIgnoredName = ignoredIngredientNames.contains { entry.name.contains($0) }
        let hasUnit = !entry.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return !hasIgnoredName && normalizedWeight(of: entry) > 0 && hasUnit
    }

    /// The amount in its base unit. Computed rather than read from the recipe:
    /// a stored value can predate an edit, and a cloud recipe may carry none.
    private func normalizedWeight(of entry: ShoppingCartEntry) -> Double {
        calcWeight.calcIngredientWeight(
            weight: entry.weight,
            unit: entry.unit,
            name: entry.name,
            num: entry.num,
            denom: entry.denom
        )
    }

    private func merge(_ entry: ShoppingCartEntry, into shoppingCart: ShoppingCart) {
        let ingredientName = IngredientNameNormalizer.displayName(entry.name)
        let comparisonKey = IngredientNameNormalizer.comparisonKey(entry.name)

        guard let existing = shoppingCart.ingredientsArray.first(where: {
            IngredientNameNormalizer.comparisonKey($0.name) == comparisonKey
        }) else {
            addNewShoppingCartIngredient(
                from: entry,
                normalizedName: ingredientName,
                to: shoppingCart
            )
            return
        }

        existing.name = ingredientName

        if (existing.unit ?? "") == entry.unit {
            existing.weight += entry.weight
            existing.normWeight += normalizedWeight(of: entry)
            addFractions(from: entry, to: existing)
        } else {
            mergeWithUnitConversion(entry, into: existing)
        }
    }

    private func addNewShoppingCartIngredient(
        from entry: ShoppingCartEntry,
        normalizedName: String,
        to shoppingCart: ShoppingCart
    ) {
        let newIngredient = Ingredient(context: viewContext)
        newIngredient.id = UUID()
        newIngredient.name = normalizedName
        newIngredient.unit = entry.unit
        newIngredient.weight = entry.weight
        newIngredient.num = entry.num
        newIngredient.denom = entry.denom
        newIngredient.normWeight = normalizedWeight(of: entry)
        newIngredient.number = 0

        shoppingCart.addToIngredients(newIngredient)
    }

    private func addFractions(from ingredient: Ingredient, to existing: Ingredient) {
        addFractions(num: ingredient.num, denom: ingredient.denom, to: existing)
    }

    private func addFractions(from entry: ShoppingCartEntry, to existing: Ingredient) {
        addFractions(num: entry.num, denom: entry.denom, to: existing)
    }

    private func addFractions(num: Int, denom: Int, to existing: Ingredient) {
        guard existing.denom != 0, denom != 0 else { return }
        guard existing.num != 0 || num != 0 else { return }

        let combinedNum = (existing.num * denom) + (num * existing.denom)
        let combinedDenom = existing.denom * denom
        let gcd = Rational.greatestCommonDivisor(combinedNum, combinedDenom)

        guard gcd != 0 else { return }
        existing.num = combinedNum / gcd
        existing.denom = combinedDenom / gcd
    }

    /// Converts the entry into the unit already on the list and adds it there.
    /// Returns false when the two units share no base unit, so the caller can
    /// put the amount on a line of its own instead of losing it.
    @discardableResult
    private func mergeWithUnitConversion(_ entry: ShoppingCartEntry, into existing: Ingredient) -> Bool {
        unitSetSc = UnitSetFB()
        unitSetNew = UnitSetFB()

        guard let existingUnit = existing.unit, !existingUnit.isEmpty else { return false }
        guard !entry.unit.isEmpty else { return false }

        for unitSet in GlobalVariables.unitSets {
            if entry.unit.localizedLowercase.contains(unitSet.name) || entry.unit == unitSet.abbreviation {
                unitSetNew = unitSet
            }
            if existingUnit.localizedLowercase.contains(unitSet.name) || existingUnit == unitSet.abbreviation {
                unitSetSc = unitSet
            }
        }

        guard !unitSetSc.baseUnit.isEmpty, unitSetSc.baseUnit == unitSetNew.baseUnit else { return false }
        guard unitSetSc.factor != 0 else { return false }

        existing.weight += entry.weight / unitSetSc.factor * unitSetNew.factor
        existing.normWeight += normalizedWeight(of: entry) / unitSetSc.factor * unitSetNew.factor
        addConvertedFractions(from: entry, to: existing)
        return true
    }

    private func addConvertedFractions(from entry: ShoppingCartEntry, to existing: Ingredient) {
        guard existing.denom != 0, entry.denom != 0 else { return }
        guard existing.num != 0 || entry.num != 0 else { return }

        let num = Int((Double(existing.num * entry.denom) * unitSetSc.factor) + (Double(entry.num * existing.denom) * unitSetNew.factor))
        let denom = existing.denom * entry.denom
        let gcd = Rational.greatestCommonDivisor(num, denom)

        guard gcd != 0 else { return }
        existing.num = num / gcd
        existing.denom = denom / gcd
    }
}
