//
//  KitchenMenuTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("A menu of several dishes as one plan")
struct KitchenMenuTests {

    private let starter = KitchenDish(id: "s", name: "Salat", tasks: [
        KitchenTask(id: "wash", name: "Salat waschen", component: "Salat", hands: 4, ingredientIDs: ["leaves"]),
        KitchenTask(id: "dress", name: "Anmachen", component: "Salat", hands: 2, after: ["wash"]),
    ], ingredients: [KitchenIngredient(id: "leaves", name: "Blattsalat", amount: 200, unit: "g", component: "Salat")])

    private let main = KitchenDish(id: "m", name: "Pasta", tasks: [
        KitchenTask(id: "boil", name: "Nudeln kochen", component: "", hands: 2, unattended: 9, station: .burner),
        KitchenTask(id: "sauce", name: "Sauce", component: "", hands: 6, station: .burner),
        KitchenTask(id: "plate", name: "Anrichten", component: "", hands: 2, after: ["boil", "sauce"]),
    ])

    @Test("Steps and ingredients keep their course as a prefix, nothing collides, and the plan goes through")
    func combined() throws {
        let menu = KitchenMenu.combined(name: "Abendessen", courses: [
            KitchenMenuCourse(dish: starter, label: "Vorspeise", gapAfterMinutes: 20),
            KitchenMenuCourse(dish: main, label: "Hauptgang"),
        ], id: "menu") { "\($0) servieren" }
        #expect(menu.source == .menu)
        #expect(Set(menu.tasks.map(\.id)).count == menu.tasks.count)
        #expect(menu.tasks.map(\.id).contains("c0-serve"))
        #expect(menu.ingredients.count == 1)
        #expect(menu.ingredients[0].component == "Vorspeise – Salat")
        #expect(menu.tasks.first { $0.id == "c0-wash" }?.ingredientIDs == ["c0-leaves"])
        #expect(menu.tasks.first { $0.id == "c1-plate" }?.component == "Hauptgang")
        #expect(menu.tasks.first { $0.id == "c1-plate" }?.after == ["c1-boil", "c1-sauce", "c0-serve"])
        #expect(menu.consistent() == menu)
        let plan = try KitchenScheduler.schedule(menu.tasks, kitchen: Kitchen(burners: 2, ovens: 0))
        let served = try #require(plan.placement(of: "c0-dress"))
        let serve = try #require(plan.placement(of: "c0-serve"))
        let plated = try #require(plan.placement(of: "c1-plate"))
        // The starter is on the table at least the gap before the main is plated.
        #expect(serve.start >= served.end)
        #expect(serve.end - serve.start == 20)
        #expect(plated.start >= serve.end)
        #expect(plated.start - served.end >= 20)
    }

    @Test("Without a gap the courses are served together: the next course's finals wait for the previous ones")
    func noGap() throws {
        let menu = KitchenMenu.combined(name: "Zusammen", courses: [
            KitchenMenuCourse(dish: starter, label: "Salat", gapAfterMinutes: 0),
            KitchenMenuCourse(dish: main, label: "Pasta"),
        ]) { "\($0) servieren" }
        #expect(!menu.tasks.contains { $0.id == "c0-serve" })
        #expect(menu.tasks.first { $0.id == "c1-plate" }?.after == ["c1-boil", "c1-sauce", "c0-dress"])
        #expect(throws: Never.self) { try KitchenScheduler.schedule(menu.tasks, kitchen: Kitchen(burners: 2, ovens: 0)) }
    }

    @Test("Three sample dishes make one menu that still plans")
    func samples() throws {
        let courses = KitchenSampleDishes.all.enumerated().map { index, dish in
            KitchenMenuCourse(dish: dish, label: "Gang \(index + 1)", gapAfterMinutes: 15)
        }
        let menu = KitchenMenu.combined(name: "Drei Gänge", courses: courses) { "\($0) servieren" }
        #expect(menu.tasks.count == KitchenSampleDishes.all.map(\.tasks.count).reduce(0, +) + 2)
        #expect(menu.ingredients.count == KitchenSampleDishes.all.map(\.ingredients.count).reduce(0, +))
        let plan = try KitchenScheduler.schedule(menu.tasks)
        #expect(plan.makespan > KitchenSampleDishes.all.map { (try? KitchenScheduler.schedule($0.tasks).makespan) ?? 0 }.max()!)
    }
}
