import Foundation
import Testing
@testable import BakePlannerCore

@Suite("CookPlanner: dishes as a file")
struct KitchenDishTransferTests {

    private func dish(_ id: String, _ name: String = "Gericht", source: KitchenDishSource = .manual) -> KitchenDish {
        KitchenDish(id: id, name: name, source: source, tasks: [KitchenTask(id: "t", name: "Schritt", hands: 5)])
    }

    @Test("Known dishes and examples stay, new ones come in once")
    func merge() throws {
        let example = try #require(KitchenSampleDishes.all.first)
        let result = KitchenDishTransfer.merge([dish("a", "Neu"), dish("b", "Geändert"), example, dish("a")],
                                               into: [dish("b")])
        #expect(result.added.map(\.id) == ["a"])
        #expect(result.added.first?.name == "Neu")
        #expect(result.alreadyThere == 3)
    }

    @Test("An unknown example comes in as an own dish")
    func unknownExample() {
        let result = KitchenDishTransfer.merge([dish("old-sample", source: .sample)], into: [], examples: [])
        #expect(result.added.first?.source == .manual)
    }

    @Test("A backup round trip keeps the dishes")
    func roundTrip() throws {
        let dishes = [dish("a", "Eins"), dish("b", "Zwei")]
        let data = try KitchenDishFile(dishes: dishes).encoded()
        #expect(try KitchenDishFile.decode(data).kitchenDishes == dishes)
    }

    @Test("File names: the dish for one, the day for several")
    func fileNames() {
        #expect(KitchenDishTransfer.fileName(for: [dish("a", "Lachs / Dill")]) == "Lachs   Dill.cookplanner")
        var parts = DateComponents()
        parts.year = 2026; parts.month = 11; parts.day = 21; parts.hour = 12
        let date = Calendar(identifier: .gregorian).date(from: parts)!
        #expect(KitchenDishTransfer.fileName(for: [dish("a"), dish("b")], date: date) == "CookPlanner 2026-11-21.cookplanner")
    }
}
