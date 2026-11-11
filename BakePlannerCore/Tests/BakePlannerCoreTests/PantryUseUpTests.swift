import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Pantry: using up what runs out soon, and when to remind")
struct PantryUseUpTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func ingredient(_ name: String, _ weight: Double, _ unit: String = "g") -> RecipeExportIngredient {
        RecipeExportIngredient(name: name, number: 1, unit: unit, weight: weight, normWeight: weight, num: 0, denom: 0)
    }

    private func recipe(_ ingredients: [RecipeExportIngredient]) -> RecipeExportData {
        RecipeExportData(name: "R", summary: "", prepTime: 0, totalWeight: 1_000, tags: [], rating: 0, recurrenceIntervalDays: 0,
                         components: [RecipeExportComponent(name: "Teig", number: 1, ingredients: ingredients)], instructions: [])
    }

    @Test("Only soon-expiring items count, the recipe uses no more than is there, most first")
    func useUp() {
        let now = date(11)
        let pantry = [
            StoredPantryItem(id: "rye", name: "Roggenmehl 1150", amount: 300, unit: .gram, bestBefore: date(20)),
            StoredPantryItem(id: "wheat", name: "Weizenmehl 550", amount: 2, unit: .kilogram, bestBefore: date(15)),
            StoredPantryItem(id: "spelt", name: "Dinkelmehl 630", amount: 1, unit: .kilogram, bestBefore: date(30)),
            StoredPantryItem(id: "eggs", name: "Ei", amount: 6, unit: .piece, bestBefore: date(14)),
        ]
        let bread = recipe([ingredient("Roggenmehl 1150", 500), ingredient("Weizenmehl 550", 400),
                            ingredient("Dinkelmehl 630", 100), ingredient("Ei", 2, "St"), ingredient("Wasser", 600)])
        let uses = PantryMatcher.useUp(bread, scale: 1, pantry: pantry, now: now, calendar: calendar)
        #expect(uses.map(\.item.id) == ["wheat", "rye", "eggs"])
        #expect(uses[0].usedBase == 400 && uses[1].usedBase == 300 && uses[2].usedBase == 2)
        #expect(PantryMatcher.useUpScore(uses) == 400 + 300 + 120)
        // A recipe without any of them: nothing to use up.
        let cake = recipe([ingredient("Dinkelmehl 630", 300), ingredient("Zucker", 100)])
        #expect(PantryMatcher.useUp(cake, scale: 1, pantry: pantry, now: now, calendar: calendar).isEmpty)
        // Nothing runs out soon: nothing either.
        let fresh = pantry.map { var item = $0; item.bestBefore = date(30); return item }
        #expect(PantryMatcher.useUp(bread, scale: 1, pantry: fresh, now: now, calendar: calendar).isEmpty)
    }

    @Test("The reminder comes fourteen days before, at nine; none without a date or once that is past")
    func reminderDate() {
        let now = date(11, hour: 8)
        let flour = StoredPantryItem(id: "a", name: "Mehl", amount: 1, unit: .kilogram, bestBefore: date(30, hour: 18))
        #expect(Pantry.reminderDate(for: flour, now: now, calendar: calendar) == date(16, hour: 9))
        let undated = StoredPantryItem(id: "b", name: "Mehl", amount: 1, unit: .kilogram)
        #expect(Pantry.reminderDate(for: undated, now: now, calendar: calendar) == nil)
        let soon = StoredPantryItem(id: "c", name: "Hefe", amount: 1, unit: .piece, bestBefore: date(20))
        #expect(Pantry.reminderDate(for: soon, now: now, calendar: calendar) == nil)
    }
}
