//
//  PantryCheckCard.swift
//  BackPlaner
//
//  On a recipe's page: what of the recipe is in the pantry at the amount
//  shown, and what is missing. Shown only while the pantry has anything
//  in it; the reading is PantryMatcher in the package.
//

import BakePlannerCore
import CoreData
import SwiftUI

struct PantryCheckCard: View {

    /// The recipe as the page shows it; built by the page.
    let recipe: RecipeExportData
    /// The serving factor chosen on the page.
    let scale: Double

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var managedItems: FetchedResults<PantryItem>
    @FetchRequest(sortDescriptors: [])
    private var managedReservations: FetchedResults<PantryReservation>

    var body: some View {
        // What is free: the stock less what open plans have reserved.
        let pantry = PantryLedger.available(managedItems.map(CoreDataPantryStore.stored),
                                            reservations: managedReservations.compactMap(CoreDataPantryReservationStore.stored))
        if !pantry.isEmpty {
            let check = PantryMatcher.check(recipe, scale: scale, pantry: pantry)
            if !check.needs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Vorrat", systemImage: "shippingbox")
                        .font(Theme.brandFont(15))
                        .foregroundColor(Theme.cardTitle)
                    if check.isComplete {
                        Label("Alle \(check.needs.count) Zutaten sind im Vorrat.", systemImage: "checkmark.circle")
                            .font(Theme.bodyFont(14))
                            .foregroundColor(Theme.subtitle)
                    } else {
                        Text("\(check.covered.count) von \(check.needs.count) Zutaten im Vorrat")
                            .font(Theme.bodyFont(14))
                            .foregroundColor(Theme.subtitle)
                        ForEach(check.missing, id: \.name) { need in
                            let amount = PantryMatcher.baseText(need.missingBase, counted: need.isCounted, locale: AppSettings.locale)
                            Label {
                                Text("Es fehlen \(amount) \(need.name)")
                            } icon: {
                                Image(systemName: "minus.circle")
                            }
                            .font(Theme.bodyFont(14))
                            .foregroundColor(Theme.warning)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("recipe.pantryCheck")
            }
        }
    }
}
