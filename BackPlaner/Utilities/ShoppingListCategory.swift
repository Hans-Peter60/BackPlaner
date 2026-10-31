//
//  ShoppingListCategory.swift
//  BackPlaner
//
//  How the shelves of a shopping list look in the iOS app. Which ingredient
//  goes on which shelf is decided in BakePlannerCore.
//

import BakePlannerCore
import SwiftUI

extension ShoppingListCategory {

    /// The heading above the group.
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

    var systemImage: String {
        switch self {
        case .flourAndGrain:        return "leaf"
        case .dairyAndEggs:         return "refrigerator"
        case .bakingSupplies:       return "birthday.cake"
        case .nutsSeedsDriedFruit:  return "allergens"
        case .fruitAndVegetables:   return "carrot"
        case .spicesAndHerbs:       return "sparkles"
        case .fatsAndLiquids:       return "drop.fill"
        case .other:                return "basket"
        }
    }
}
