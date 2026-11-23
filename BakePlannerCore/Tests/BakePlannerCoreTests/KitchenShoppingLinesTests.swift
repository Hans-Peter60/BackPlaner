import Foundation
import Testing
@testable import BakePlannerCore

@Suite("CookPlanner: one shopping line per thing to buy")
struct KitchenShoppingLinesTests {

    private let german = Locale(identifier: "de_DE")

    @Test("The example's butter, oil, salt and pepper are one line each, amounts added up")
    func example() throws {
        let dish = KitchenSampleDishes.perlhuhnbrust
        let lines = KitchenShoppingList.lines(of: dish)
        let butter = try #require(lines.first { $0.name == "Butter" })
        // 30 + 20 + 20 + 15 g from four components.
        #expect(butter.text(locale: german) == "85 g Butter")
        #expect(butter.ingredientIDs.count == 4)
        #expect(butter.components == ["Perlhuhnbrust", "Wirsing", "Kräuterseitlinge", "Verjus-Birne"])
        #expect(lines.filter { $0.name == "Salz" }.count == 1)
        #expect(lines.first { $0.name == "Neutrales Öl" }?.text(locale: german) == "2 EL Neutrales Öl")
        #expect(lines.count < dish.ingredients.count)
    }

    @Test("Grams join kilograms, other units stand side by side, a single note stays")
    func units() {
        let dish = KitchenDish(id: "d", name: "Test", tasks: [], ingredients: [
            KitchenIngredient(id: "1", name: "Mehl", amount: 800, unit: "g", component: "A"),
            KitchenIngredient(id: "2", name: "Mehl", amount: 0.5, unit: "kg", component: "B"),
            KitchenIngredient(id: "3", name: "Butter", amount: 50, unit: "g", component: "A"),
            KitchenIngredient(id: "4", name: "Butter", amount: 1, unit: "EL", component: "B"),
            KitchenIngredient(id: "5", name: "Zwiebel", amount: 1, component: "A"),
            KitchenIngredient(id: "6", name: "Zwiebel", amount: 2, unit: "Stück", component: "B"),
            KitchenIngredient(id: "7", name: "Schalotte", amount: 1, component: "A", note: "klein"),
        ])
        let texts = KitchenShoppingList.lines(of: dish).map { $0.text(locale: german) }
        #expect(texts == ["1,3 kg Mehl", "50 g + 1 EL Butter", "3 Zwiebel", "1 Schalotte (klein)"])
    }

    @Test("Shared lines: only what is not wholly at home, once")
    func missing() {
        let dish = KitchenSampleDishes.perlhuhnbrust
        let butterIDs = dish.ingredients.filter { $0.name == "Butter" }.map(\.id)
        let some = KitchenShoppingList.missingLines(for: dish, available: [butterIDs[0]], locale: german)
        #expect(some.components(separatedBy: "\n").filter { $0.hasSuffix("Butter") } == ["85 g Butter"])
        let none = KitchenShoppingList.missingLines(for: dish, available: Set(butterIDs), locale: german)
        #expect(!none.contains("Butter"))
    }

    @Test("Pieces added up from single ones read in the plural, in German only")
    func plurals() {
        let dish = KitchenDish(id: "d", name: "Test", tasks: [], ingredients: [
            KitchenIngredient(id: "1", name: "Knoblauchzehe", amount: 1, component: "A"),
            KitchenIngredient(id: "2", name: "Knoblauchzehe", amount: 2, component: "B"),
            KitchenIngredient(id: "3", name: "Zwiebel", amount: 1, component: "A"),
            KitchenIngredient(id: "4", name: "Zwiebel", amount: 1, component: "B"),
            KitchenIngredient(id: "5", name: "Birne", amount: 1, component: "A"),
            KitchenIngredient(id: "6", name: "Ei", amount: 1, component: "A"),
            KitchenIngredient(id: "7", name: "Ei", amount: 1, component: "B"),
        ])
        let lines = KitchenShoppingList.lines(of: dish)
        // "Knoblauchzehe" ×2 in one ingredient is taken as the recipe's own wording.
        #expect(lines.map { $0.text(locale: german) } == ["3 Knoblauchzehe", "2 Zwiebeln", "1 Birne", "2 Eier"])
        #expect(lines.map { $0.text(locale: Locale(identifier: "en_US")) }[1] == "2 Zwiebel")
        let pieces = KitchenDish(id: "e", name: "Test", tasks: [], ingredients: [
            KitchenIngredient(id: "1", name: "Knoblauchzehe", amount: 1, component: "A"),
            KitchenIngredient(id: "2", name: "Knoblauchzehe", amount: 1, component: "B"),
            KitchenIngredient(id: "3", name: "Knoblauchzehe", amount: 1, component: "C"),
        ])
        #expect(KitchenShoppingList.lines(of: pieces).first?.text(locale: german) == "3 Knoblauchzehen")
    }
}
