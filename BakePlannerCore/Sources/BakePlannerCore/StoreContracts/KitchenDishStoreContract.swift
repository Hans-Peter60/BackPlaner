//
//  KitchenDishStoreContract.swift
//  BakePlannerCore
//
//  What every KitchenDishStore must do, written once and checked against
//  each store: in memory and SQLite. Each check takes a new, empty store
//  and throws ContractViolation when the store behaves differently.
//

import Foundation

public enum KitchenDishStoreContract {

    public typealias Check = (KitchenDishStore) throws -> Void

    public static let checks: [(name: String, run: Check)] = [
        ("an empty store has nothing", emptyStore),
        ("a dish comes back as it was kept, every field of every step", saveAndRead),
        ("dishes come by name", order),
        ("keeping a dish again replaces it whole, steps included", replace),
        ("a removed dish is gone, the others stay; an unknown id removes nothing", delete),
        ("a dish without a name or id is refused", incomplete),
    ]

    // MARK: Checks

    public static func emptyStore(_ store: KitchenDishStore) throws {
        try expect(store.dishes().isEmpty, "an empty store has dishes")
        try expect(store.dish(id: "none") == nil, "an empty store finds a dish")
    }

    public static func saveAndRead(_ store: KitchenDishStore) throws {
        let dish = sampleDish()
        try store.save(dish)
        let read = try store.dish(id: dish.id)
        try expect(read == dish, "the dish read differs from the one kept: \(String(describing: read))")
        try expect(store.dishes() == [dish], "the list differs from the one dish kept")
        // The example dishes, with windows, temperatures and waits.
        for sample in KitchenSampleDishes.all {
            try store.save(sample)
            try expect(store.dish(id: sample.id) == sample, "\(sample.name) read differs from the one kept")
        }
    }

    public static func order(_ store: KitchenDishStore) throws {
        let b = KitchenDish(id: "b", name: "Bratkartoffeln", tasks: [step("b1")])
        let a = KitchenDish(id: "a", name: "Apfelmus", tasks: [step("a1")])
        let c = KitchenDish(id: "c", name: "Zander", tasks: [step("c1")])
        try store.save(c)
        try store.save(b)
        try store.save(a)
        let names = try store.dishes().map(\.name)
        try expect(store.dishes().map(\.id) == ["a", "b", "c"], "the dishes do not come by name: \(names)")
    }

    public static func replace(_ store: KitchenDishStore) throws {
        var dish = sampleDish()
        try store.save(dish)
        dish.name = "Lachs mit Spargel"
        dish.servings = 4
        dish.tasks = [step("x", name: "Alles auf einmal", hands: 30)]
        try store.save(dish)
        try expect(store.dishes().count == 1, "keeping a dish again added a second one")
        let replaced = try store.dish(id: dish.id)
        try expect(replaced == dish, "the replaced dish differs: \(String(describing: replaced))")
    }

    public static func delete(_ store: KitchenDishStore) throws {
        let first = KitchenDish(id: "first", name: "Erstes", tasks: [step("f1")])
        let second = KitchenDish(id: "second", name: "Zweites", tasks: [step("s1")])
        try store.save(first)
        try store.save(second)
        try store.delete(id: "first")
        try expect(store.dishes() == [second], "the removed dish is still there, or more went")
        try store.delete(id: "none")
        try expect(store.dishes() == [second], "an unknown id removed a dish")
        try expect(store.dish(id: "first") == nil, "the removed dish can still be read")
    }

    public static func incomplete(_ store: KitchenDishStore) throws {
        do {
            try store.save(KitchenDish(id: "x", name: "   ", tasks: []))
            throw ContractViolation(description: "a dish without a name was kept")
        } catch KitchenDishStoreError.incomplete {}
        do {
            try store.save(KitchenDish(id: "", name: "Ohne Kennung", tasks: []))
            throw ContractViolation(description: "a dish without an id was kept")
        } catch KitchenDishStoreError.incomplete {}
        try expect(store.dishes().isEmpty, "a refused dish was kept after all")
    }

    // MARK: Helpers

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw ContractViolation(description: message()) }
    }

    static func step(_ id: String, name: String = "Schritt", component: String = "Hauptgang", hands: Int = 2,
                     unattended: Int = 0, station: KitchenStation? = nil, after: [String] = [],
                     maxWait: Int? = nil, window: ClosedRange<Int>? = nil, ovenTemperature: Int? = nil) -> KitchenTask {
        KitchenTask(id: id, name: name, component: component, hands: hands, unattended: unattended, station: station,
                    after: after, maxWait: maxWait, window: window, ovenTemperature: ovenTemperature)
    }

    /// A dish using every field a step has.
    public static func sampleDish() -> KitchenDish {
        KitchenDish(id: "lachs", name: "Lachs mit Kartoffelpüree", source: .text, servings: 2,
                    createdAt: Date(timeIntervalSince1970: 1_793_520_000), tasks: [
            step("k1", name: "Kartoffeln schälen", component: "Püree", hands: 4),
            step("k2", name: "Kartoffeln kochen", component: "Püree", hands: 1, unattended: 20, station: .burner, after: ["k1"], window: 18...25),
            step("k3", name: "Stampfen", component: "Püree", hands: 3, after: ["k2"], maxWait: 10),
            step("l1", name: "Lachs würzen", component: "Lachs", hands: 2),
            step("l2", name: "Lachs im Ofen", component: "Lachs", hands: 1, unattended: 12, station: .oven, after: ["l1"], maxWait: 3, ovenTemperature: 180),
            step("a", name: "Anrichten", component: "", hands: 2, after: ["k3", "l2"])
        ])
    }
}
