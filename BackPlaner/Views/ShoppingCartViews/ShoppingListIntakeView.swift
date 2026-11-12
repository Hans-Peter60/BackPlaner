//
//  ShoppingListIntakeView.swift
//  BackPlaner
//
//  "Eingekauft": the lines of a shopping list go into the pantry — but with
//  what was actually bought, not with what the recipe needs. Every line is
//  prefilled with the standard package and can be corrected before booking.
//

import BakePlannerCore
import CoreData
import SwiftUI
import os

/// The lines of a list that are about to be booked into the pantry.
struct ShoppingListIntake: Identifiable {
    let id = UUID()
    let shoppingCart: ShoppingCart
    let ingredients: [Ingredient]
    /// Whether the outcome is announced afterwards: yes for the whole list,
    /// no for a single line.
    let announces: Bool
}

/// What an intake ended with.
struct ShoppingListIntakeResult {
    let booked: Int
    /// The list had no lines left and was deleted.
    let finished: Bool
}

/// How a shopping-list line reads: the package to buy, the recipe's need in
/// brackets — "500 g Weizenmehl 550 (200 g)" — or just the need when there
/// is no standard package or the package is the need.
enum ShoppingLineText {

    static func text(for ingredient: Ingredient) -> String {
        let needed = neededText(for: ingredient)
        guard let package = package(for: ingredient) else { return needed + ingredient.name }
        return PantryItemEditorView.amountText(amount: package.amount, unit: package.unit) + " " + ingredient.name
            + " (" + needed.trimmingCharacters(in: .whitespaces) + ")"
    }

    /// The recipe's amount as the row always showed it, with a trailing space.
    static func neededText(for ingredient: Ingredient) -> String {
        Rational.getPortion(unit: ingredient.unit ?? "", weight: ingredient.weight,
                            num: ingredient.num, denom: ingredient.denom, targetServings: 2)
    }

    /// What the line needs in pantry terms: grams, kilograms or pieces.
    static func need(for ingredient: Ingredient) -> (amount: Double, unit: PantryUnit) {
        Pantry.intake(unit: ingredient.unit, weight: ingredient.weight, normWeight: ingredient.normWeight,
                      num: ingredient.num, denom: ingredient.denom)
    }

    /// The standard package covering the need, when there is one and it is
    /// more than the need itself.
    static func package(for ingredient: Ingredient) -> (amount: Double, unit: PantryUnit)? {
        let need = need(for: ingredient)
        guard let package = PackageSizes.package(name: ingredient.name, amount: need.amount, unit: need.unit),
              PackageSizes.differs(package, from: need.amount, unit: need.unit) else { return nil }
        return package
    }
}

struct ShoppingListIntakeView: View {

    let intake: ShoppingListIntake
    let onBooked: (ShoppingListIntakeResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var lines: [Line]

    struct Line: Identifiable {
        let id: NSManagedObjectID
        let ingredient: Ingredient
        /// The recipe's amount, for the small print.
        let needed: String
        var amount: Double
        var unit: PantryUnit
    }

    init(intake: ShoppingListIntake, onBooked: @escaping (ShoppingListIntakeResult) -> Void) {
        self.intake = intake
        self.onBooked = onBooked
        _lines = State(initialValue: intake.ingredients.map { ingredient in
            let bought = ShoppingLineText.package(for: ingredient) ?? ShoppingLineText.need(for: ingredient)
            return Line(id: ingredient.objectID, ingredient: ingredient,
                        needed: ShoppingLineText.neededText(for: ingredient).trimmingCharacters(in: .whitespaces),
                        amount: bought.amount, unit: bought.unit)
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($lines) { $line in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.ingredient.name)
                                    .font(Theme.bodyFont(15))
                                Text("Benötigt: \(line.needed)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            NumberField("", value: $line.amount)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: scaledLayoutValue(72))
                                .accessibilityLabel("Gekaufte Menge")
                            Picker("Einheit", selection: $line.unit) {
                                ForEach(PantryUnit.allCases) { unit in
                                    Text(PantryItemEditorView.unitTitle(unit)).tag(unit)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                            // g ↔ kg keeps the quantity: 500 g become 0,5 kg,
                            // not 500 kg. Pieces have no conversion.
                            .onChange(of: line.unit) { old, new in
                                if let from = old.grams, let to = new.grams {
                                    line.amount = line.amount * from / to
                                }
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(line.ingredient.name)
                    }
                } footer: {
                    Text("Vorgeschlagen sind übliche Gebindegrößen. Trage ein, was Du wirklich gekauft hast. Eine leere Menge lässt die Zeile auf der Liste.")
                }
            }
            .clearScrollBackground()
            .warmBackground()
            .navigationTitle(Text("Eingekauft"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Short, so the title stays visible beside it.
                    Button("Buchen") { book() }
                        .disabled(!lines.contains { $0.amount > 0 })
                        .accessibilityIdentifier("shopping.intake.book")
                }
                // The number pad has no return key.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }

    /// Books every line with an amount onto the item of the same name — or a
    /// new one — and takes it off the list. Lines left at 0 stay; a list
    /// without lines is deleted.
    private func book() {
        let store = CoreDataPantryStore(context: viewContext)
        var booked = 0
        for line in lines where line.amount > 0 {
            do {
                try store.receive(name: line.ingredient.name, amount: line.amount, unit: line.unit)
                viewContext.delete(line.ingredient)
                booked += 1
            } catch {
                AppLog.shoppingCart.error("Booking a shopping-list line into the pantry failed: \(error)")
            }
        }
        let finished = intake.shoppingCart.ingredientsArray.allSatisfy(\.isDeleted)
        if finished {
            viewContext.delete(intake.shoppingCart)
        }
        do {
            try viewContext.save()
        } catch {
            AppLog.shoppingCart.error("Einkaufsliste konnte nicht in den Vorrat gebucht werden: \(error)")
        }
        onBooked(ShoppingListIntakeResult(booked: booked, finished: finished))
        dismiss()
    }
}
