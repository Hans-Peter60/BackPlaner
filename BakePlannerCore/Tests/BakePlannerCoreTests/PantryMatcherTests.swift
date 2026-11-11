import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Pantry matcher: a recipe against what is in the house")
struct PantryMatcherTests {

    private func ingredient(_ name: String, _ weight: Double, _ unit: String = "g", num: Int = 0, denom: Int = 0) -> RecipeExportIngredient {
        RecipeExportIngredient(name: name, number: 1, unit: unit, weight: weight, normWeight: weight, num: num, denom: denom)
    }

    private var bread: RecipeExportData {
        RecipeExportData(name: "Mischbrot", summary: "", prepTime: 0, totalWeight: 1_000, tags: [], rating: 0, recurrenceIntervalDays: 0,
                         components: [
                            RecipeExportComponent(name: "Sauerteig", number: 1, ingredients: [
                                ingredient("Roggenmehl 1150", 200), ingredient("Wasser", 200), ingredient("Anstellgut", 20)]),
                            RecipeExportComponent(name: "Hauptteig", number: 2, ingredients: [
                                ingredient("Roggenmehl 1150", 300), ingredient("Weizenmehl 1050", 200), ingredient("Salz", 12),
                                ingredient("Hefe", 5), ingredient("Ei", 1, "St"), ingredient("Sauerteig", 420)]),
                         ], instructions: [])
    }

    private func item(_ id: String, _ name: String, _ amount: Double, _ unit: PantryUnit, bestBefore: Date? = nil) -> StoredPantryItem {
        StoredPantryItem(id: id, name: name, amount: amount, unit: unit, bestBefore: bestBefore)
    }

    @Test("Needs merge across components; water, salt and the starter are not needs")
    func needs() {
        let check = PantryMatcher.check(bread, scale: 1, pantry: [])
        #expect(check.needs.map(\.name) == ["Roggenmehl 1150", "Weizenmehl 1050", "Hefe", "Ei"])
        #expect(check.needs[0].requiredBase == 500)
        #expect(check.needs[3].isCounted && check.needs[3].requiredBase == 1)
        #expect(!check.isComplete && check.missing.count == 4)
    }

    @Test("Covered, partly covered and missing, at the recipe's scale")
    func coverage() {
        let pantry = [item("a", "roggenmehl 1150", 1, .kilogram), item("b", "Weizenmehl 1050", 150, .gram),
                      item("c", "Eier", 6, .piece), item("d", "Hefe", 42, .gram)]
        let check = PantryMatcher.check(bread, scale: 1, pantry: pantry)
        #expect(check.covered.map(\.name) == ["Roggenmehl 1150", "Hefe"])
        #expect(check.missing.map(\.name) == ["Weizenmehl 1050", "Ei"])
        #expect(check.missing[0].missingBase == 50)
        // Doubled: the rye and the yeast still fit, the wheat is further off.
        let doubled = PantryMatcher.check(bread, scale: 2, pantry: pantry)
        #expect(doubled.covered.map(\.name) == ["Roggenmehl 1150", "Hefe"])
        #expect(doubled.missing.first?.missingBase == 250)
        // Everything there: complete.
        let full = pantry + [item("e", "Weizenmehl 1050", 1, .kilogram), item("f", "Ei", 2, .piece)]
        #expect(PantryMatcher.check(bread, scale: 1, pantry: full).isComplete)
        #expect(!PantryMatcher.check(RecipeExportData(name: "Leer", summary: "", prepTime: 0, totalWeight: 0, tags: [], rating: 0,
                                                        recurrenceIntervalDays: 0, components: [], instructions: []),
                                     scale: 1, pantry: full).isComplete)
    }

    @Test("The shopping list leaves out what is in the house and shrinks partial lines")
    func reduce() {
        let entries = ShoppingListBuilder.entriesToBuy(ShoppingListBuilder.entries(of: bread), scale: 1)
        let pantry = [item("a", "Roggenmehl 1150", 1, .kilogram), item("b", "Weizenmehl 1050", 150, .gram),
                      item("c", "Hefe", 2, .gram)]
        let reduced = PantryMatcher.reduce(entries, pantry: pantry)
        let byName = Dictionary(uniqueKeysWithValues: reduced.map { (IngredientNameNormalizer.comparisonKey($0.name), $0) })
        #expect(byName["roggenmehl 1150"] == nil)
        #expect(byName["weizenmehl 1050"]?.weight == 50)
        #expect(byName["hefe"]?.weight == 3)
        #expect(byName["ei"]?.weight == 1)
        // Without a pantry nothing changes.
        #expect(PantryMatcher.reduce(entries, pantry: []) == entries)
        // Kilogram lines and spoons need the unit tables, which the package
        // tests may run without; the app's tests cover them.
        guard !GlobalVariables.bundledUnitSets.isEmpty else { return }
        let kilo = [ShoppingListEntry(name: "Dinkelmehl 630", unit: "kg", weight: 1.5, num: 0, denom: 0)]
        #expect(PantryMatcher.reduce(kilo, pantry: [item("d", "Dinkelmehl 630", 400, .gram)]).first?.weight == 1.1)
        // A spoon of something partly covered stays whole: no way to shrink "EL".
        let spoon = [ShoppingListEntry(name: "Honig", unit: "EL", weight: 2, num: 0, denom: 0)]
        #expect(PantryMatcher.reduce(spoon, pantry: [item("e", "Honig", 5, .gram)]).first?.weight == 2)
    }

    @Test("A bake takes from the soonest-expiring item first, no further than it reaches")
    func deductions() {
        let soon = Date(timeIntervalSince1970: 1_800_000_000)
        let later = Date(timeIntervalSince1970: 1_900_000_000)
        let pantry = [item("late", "Roggenmehl 1150", 1, .kilogram, bestBefore: later),
                      item("soon", "Roggenmehl 1150", 300, .gram, bestBefore: soon),
                      item("w", "Weizenmehl 1050", 150, .gram),
                      item("h", "Hefe", 2, .piece)]
        let deductions = PantryMatcher.deductions(for: bread, scale: 1, pantry: pantry)
        #expect(deductions.map(\.item.id) == ["soon", "late", "w"])
        #expect(deductions[0].taken == 300 && deductions[0].remaining == 0)
        #expect(deductions[1].taken == 0.2 && deductions[1].remaining == 0.8)
        #expect(deductions[2].taken == 150 && deductions[2].remaining == 0)
    }

    @Test("Amounts read as grams, kilograms or pieces")
    func texts() {
        let de = Locale(identifier: "de_DE")
        #expect(PantryMatcher.baseText(200, counted: false, locale: de) == "200 g")
        #expect(PantryMatcher.baseText(1_250, counted: false, locale: de) == "1,25 kg")
        #expect(PantryMatcher.baseText(2.2, counted: true, locale: de) == "3 Stück")
        #expect(PantryMatcher.baseText(8.5, counted: false, locale: de) == "8,5 g")
        #expect(PantryMatcher.baseText(12.4, counted: false, locale: de) == "12 g")
    }
}
