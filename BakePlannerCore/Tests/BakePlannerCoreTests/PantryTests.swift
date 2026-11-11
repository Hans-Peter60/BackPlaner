import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Pantry contract: in memory")
struct InMemoryPantryStoreTests {
    @Test("Every check of the contract", arguments: PantryStoreContract.checks.map(\.name))
    func contract(_ name: String) throws {
        let check = try #require(PantryStoreContract.checks.first { $0.name == name })
        try check.run(InMemoryPantryStore())
    }
}

@Suite("Pantry: shelf life and name suggestions")
struct PantryTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test("Fresh beyond two weeks, soon within, expired after; no date is unknown")
    func shelfLife() {
        let now = date(11, hour: 9)
        #expect(PantryShelfLife.of(nil, now: now, calendar: calendar) == .unknown)
        #expect(PantryShelfLife.of(date(26), now: now, calendar: calendar) == .fresh)
        #expect(PantryShelfLife.of(date(25), now: now, calendar: calendar) == .soon(days: 14))
        #expect(PantryShelfLife.of(date(11, hour: 23), now: now, calendar: calendar) == .soon(days: 0))
        #expect(PantryShelfLife.of(date(10, hour: 23), now: now, calendar: calendar) == .expired(days: 1))
        #expect(PantryShelfLife.of(date(10), now: now, calendar: calendar).needsAttention)
        #expect(!PantryShelfLife.of(date(26), now: now, calendar: calendar).needsAttention)
    }

    @Test("Items needing attention come soonest first; the fresh and undated stay out")
    func attention() {
        let now = date(11)
        let items = [
            StoredPantryItem(id: "a", name: "Dinkel", amount: 1, unit: .kilogram, bestBefore: date(20)),
            StoredPantryItem(id: "b", name: "Hefe", amount: 1, unit: .piece, bestBefore: date(5)),
            StoredPantryItem(id: "c", name: "Roggen", amount: 1, unit: .kilogram, bestBefore: date(30)),
            StoredPantryItem(id: "d", name: "Sesam", amount: 1, unit: .kilogram),
        ]
        #expect(Pantry.needingAttention(items, now: now, calendar: calendar).map(\.id) == ["b", "a"])
    }

    @Test("Suggested names: bought ingredients of the recipes, most used first, each once")
    func suggestions() {
        func recipe(_ names: [String]) -> RecipeExportData {
            RecipeExportData(name: "R", summary: "", prepTime: 0, totalWeight: 0, tags: [], rating: 0, recurrenceIntervalDays: 0,
                             components: [RecipeExportComponent(name: "Teig", number: 1, ingredients: names.map {
                                 RecipeExportIngredient(name: $0, number: 1, unit: "g", weight: 100, normWeight: 100, num: 0, denom: 0)
                             })], instructions: [])
        }
        let names = Pantry.suggestedNames(from: [
            recipe(["Weizenmehl 550", "Wasser", "Salz", "Anstellgut", "Hefe"]),
            recipe(["weizenmehl 550 (zimmerwarm)", "Roggenmehl 1150", "Hefe"]),
            recipe(["Roggenmehl 1150", "Sesam", "Weizenmehl 550"]),
        ])
        #expect(names.first == "Weizenmehl 550")
        #expect(names.count == 4)
        #expect(!names.contains("Wasser") && !names.contains("Salz") && !names.contains("Anstellgut"))
        #expect(Pantry.matchingNames("rogg", in: names) == ["Roggenmehl 1150"])
        #expect(Pantry.matchingNames("Roggenmehl 1150", in: names).isEmpty)
        #expect(Pantry.matchingNames("", in: names) == names)
    }

    @Test("Units: kilograms are a thousand grams, pieces are counted")
    func units() {
        #expect(PantryUnit(stored: "kg").grams == 1_000)
        #expect(PantryUnit(stored: nil) == .gram)
        #expect(PantryUnit(stored: "Stück") == .gram)
        #expect(StoredPantryItem(id: "x", name: "Eier", amount: 6, unit: .piece).baseAmount == 6)
    }
}
