//
//  KitchenDishTests.swift
//  BakePlannerCoreTests
//
//  The dish, its file format, its store contract in memory, and the
//  dependency defaults.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Dishes: file format, store and defaults")
struct KitchenDishTests {

    @Test("Every dish goes through the file and comes back the same",
          arguments: KitchenSampleDishes.all + [KitchenDishStoreContract.sampleDish()])
    func roundTrip(_ dish: KitchenDish) throws {
        let data = try KitchenDishFile(dishes: [dish]).encoded()
        let read = try KitchenDishFile.decode(data)
        #expect(read.formatVersion == 2)
        #expect(read.kitchenDishes == [dish])
    }

    @Test("A file of a later version is refused; unknown fields and an unknown source are tolerated")
    func versions() throws {
        let future = Data(#"{"formatVersion": 3, "dishes": []}"#.utf8)
        #expect(throws: KitchenDishFileError.unsupportedVersion(3)) { try KitchenDishFile.decode(future) }
        let lenient = Data("""
        {"formatVersion": 1, "colour": "red", "dishes": [{"id": "x", "name": "Suppe", "source": "fax", "servings": -2,
          "steps": [{"id": "s", "name": "Kochen", "component": "", "handsMinutes": 99999999, "unattendedMinutes": 10,
                     "station": "microwave", "after": [], "windowMinimum": 12, "windowMaximum": 8, "ovenTemperature": 5000}]}]}
        """.utf8)
        let dish = try #require(try KitchenDishFile.decode(lenient).kitchenDishes.first)
        #expect(dish.source == .manual && dish.servings == 0)
        let step = try #require(dish.tasks.first)
        #expect(step.handsMinutes == Plausible.maxMinutes)
        #expect(step.station == nil && step.unattendedWindow == nil && step.ovenTemperature == nil)
        // A format-1 file has no ingredients; the dish comes back without.
        #expect(dish.ingredients.isEmpty && step.ingredientIDs.isEmpty)
    }

    @Test("Every check of the store contract, in memory", arguments: KitchenDishStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(KitchenDishStoreContract.checks.first { $0.name == name })
        try check.run(InMemoryKitchenDishStore())
    }

    @Test("Dependencies by default: a step follows its component's previous step, the plating waits for every component")
    func defaults() {
        let tasks = KitchenDishDefaults.withDependencies([
            KitchenTask(id: "k1", name: "Kartoffeln schälen", component: "Püree", hands: 4),
            KitchenTask(id: "l1", name: "Lachs würzen", component: "Lachs", hands: 2),
            KitchenTask(id: "k2", name: "Kartoffeln kochen", component: "Püree", hands: 1, unattended: 20, station: .burner),
            KitchenTask(id: "l2", name: "Lachs braten", component: "Lachs", hands: 6, station: .burner, after: ["k1"]),
            KitchenTask(id: "g", name: "Garnitur", component: "", hands: 2),
            KitchenTask(id: "a", name: "Anrichten", component: "", hands: 2)
        ])
        #expect(tasks.map(\.after) == [[], [], ["k1"], ["k1"], [], ["k2", "l2", "g"]])
        // A single step has nothing to wait for; a dish with named predecessors keeps them.
        #expect(KitchenDishDefaults.withDependencies([KitchenTask(id: "x", name: "x", hands: 1)]).first?.after == [])
    }

    @Test("A duplicate is the cook's own, under a new identity")
    func duplicate() {
        let copy = KitchenSampleDishes.perlhuhnbrust.duplicate(now: Date(timeIntervalSince1970: 1_793_520_000))
        #expect(copy.id != KitchenSampleDishes.perlhuhnbrust.id)
        #expect(copy.source == .manual && copy.createdAt != nil)
        #expect(copy.tasks == KitchenSampleDishes.perlhuhnbrust.tasks)
        #expect(copy.components == KitchenSampleDishes.perlhuhnbrust.components)
    }
}
