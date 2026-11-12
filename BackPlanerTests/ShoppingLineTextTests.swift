//
//  ShoppingLineTextTests.swift
//  BackPlanerTests
//
//  How a shopping-list line reads once packages are known: the package to
//  buy, the recipe's need in brackets.
//

import BakePlannerCore
import CoreData
import Foundation
import Testing
@testable import BackPlaner

@Suite("Shopping-list line text: package and need")
@MainActor
struct ShoppingLineTextTests {

    private func ingredient(_ name: String, _ weight: Double, _ unit: String, normWeight: Double? = nil,
                            num: Int = 0, denom: Int = 0, in context: NSManagedObjectContext) -> Ingredient {
        let ingredient = Ingredient(context: context)
        ingredient.id = UUID()
        ingredient.number = 1
        ingredient.name = name
        ingredient.weight = weight
        ingredient.normWeight = normWeight ?? weight
        ingredient.unit = unit
        ingredient.num = num
        ingredient.denom = denom
        return ingredient
    }

    @Test("Flour names its package with the need in brackets; a need that is a package reads plain")
    func flour() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let small = ingredient("Weizenmehl 550", 200, "g", in: context)
        #expect(ShoppingLineText.text(for: small) == "1 kg Weizenmehl 550 (200 g)")
        #expect(ShoppingLineText.package(for: small)?.amount == 1)
        let exact = ingredient("Weizenmehl 550", 1, "kg", in: context)
        #expect(ShoppingLineText.text(for: exact) == "1 kg Weizenmehl 550")
        #expect(ShoppingLineText.package(for: exact) == nil)
        let flakes = ingredient("Haferflocken", 80, "g", in: context)
        #expect(ShoppingLineText.text(for: flakes) == "500 g Haferflocken (80 g)")
        let kilos = ingredient("Roggenmehl 1150", 1.2, "kg", in: context)
        #expect(ShoppingLineText.text(for: kilos) == "2 kg Roggenmehl 1150 (1,2 kg)")
    }

    @Test("Yeast by the cube, eggs by the half dozen, water as the recipe says")
    func others() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let yeast = ingredient("Hefe", 10, "g", in: context)
        #expect(ShoppingLineText.text(for: yeast) == "42 g Hefe (10 g)")
        let eggs = ingredient("Eier", 2, "St", in: context)
        #expect(ShoppingLineText.text(for: eggs) == "6 Stück Eier (2 St)")
        let water = ingredient("Wasser", 350, "g", in: context)
        #expect(ShoppingLineText.text(for: water) == "350 g Wasser")
        #expect(ShoppingLineText.package(for: water) == nil)
    }
}
