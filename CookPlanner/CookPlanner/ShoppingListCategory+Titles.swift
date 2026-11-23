//
//  ShoppingListCategory+Titles.swift
//  CookPlanner
//
//  The shelves' headings and symbols on CookPlanner's shopping list; which
//  ingredient goes on which shelf is ShoppingListCategory in the package,
//  the same as in BakePlanner.
//

import BakePlannerCore
import SwiftUI

extension ShoppingListCategory {

    var title: LocalizedStringKey {
        switch self {
        case .flourAndGrain: "Mehl & Getreide"
        case .dairyAndEggs: "Milchprodukte & Eier"
        case .bakingSupplies: "Backzutaten"
        case .nutsSeedsDriedFruit: "Nüsse, Saaten & Trockenfrüchte"
        case .fruitAndVegetables: "Obst & Gemüse"
        case .spicesAndHerbs: "Gewürze & Kräuter"
        case .fatsAndLiquids: "Öle, Fette & Flüssiges"
        case .other: "Sonstiges"
        }
    }

    var systemImage: String {
        switch self {
        case .flourAndGrain: "leaf"
        case .dairyAndEggs: "refrigerator"
        case .bakingSupplies: "birthday.cake"
        case .nutsSeedsDriedFruit: "allergens"
        case .fruitAndVegetables: "carrot"
        case .spicesAndHerbs: "sparkles"
        case .fatsAndLiquids: "drop.fill"
        case .other: "basket"
        }
    }
}
