import Foundation
import Testing
@testable import BakePlannerCore

@Suite("CookPlanner: scaling a dish's amounts")
struct KitchenPortionsTests {

    @Test("The factor follows the servings and falls back to 1")
    func factor() {
        #expect(KitchenPortions.factor(servings: 6, base: 4) == 1.5)
        #expect(KitchenPortions.factor(servings: 2, base: nil) == 1)
        #expect(KitchenPortions.factor(servings: 0, base: 4) == 1)
    }

    @Test("Counted units go to halves, weights to a step for their size")
    func rounding() {
        #expect(KitchenPortions.scaled(1, unit: "Stück", by: 1.5) == 1.5)
        #expect(KitchenPortions.scaled(1, unit: "", by: 0.25) == 0.5)
        #expect(KitchenPortions.scaled(3, unit: "Zehen", by: 0.5) == 1.5)
        #expect(KitchenPortions.scaled(1, unit: "EL", by: 1.33) == 1.5)
        #expect(KitchenPortions.scaled(200, unit: "g", by: 1.5) == 300)
        #expect(KitchenPortions.scaled(125, unit: "g", by: 1.5) == 190)
        #expect(KitchenPortions.scaled(600, unit: "g", by: 1.37) == 820)
        #expect(KitchenPortions.scaled(30, unit: "ml", by: 1.33) == 40)
        #expect(KitchenPortions.scaled(2, unit: "g", by: 0.5) == 1)
        #expect(KitchenPortions.scaled(200, unit: "g", by: 1) == 200)
    }

    @Test("Scaling a dish changes the amounts and keeps the steps")
    func dish() {
        let onion = KitchenIngredient(id: "o", name: "Zwiebel", amount: 1, unit: "Stück")
        let salt = KitchenIngredient(id: "s", name: "Salz")
        let beef = KitchenIngredient(id: "b", name: "Rinderfilet", amount: 400, unit: "g")
        let dish = KitchenDish(id: "d", name: "Test", source: .manual, servings: 2,
                               tasks: [KitchenTask(id: "t", name: "Schneiden", component: "A", hands: 5)],
                               ingredients: [onion, salt, beef])
        let scaled = dish.scaled(by: KitchenPortions.factor(servings: 3, base: dish.servings))
        #expect(scaled.ingredients.map(\.amount) == [1.5, nil, 600])
        #expect(scaled.tasks == dish.tasks)
        #expect(scaled.id == dish.id)
        #expect(dish.scaled(by: 1) == dish)
    }
}
