import Foundation
import Testing
@testable import BakePlannerCore

@Suite("CookPlanner: narrowing the dish list")
struct KitchenDishFilterTests {

    private func facets(_ dish: KitchenDish, budget: Int = 45) throws -> KitchenDishFacets {
        KitchenDishFacets(dish: dish, schedule: try KitchenScheduler.schedule(dish.tasks, kitchen: Kitchen(), budget: budget))
    }

    private let salad = KitchenDish(id: "s", name: "Salat mit Ziegenkäse", source: .text,
                                    tasks: [KitchenTask(id: "a", name: "Waschen", component: "Salat", hands: 8)],
                                    ingredients: [KitchenIngredient(name: "Feldsalat")])
    private let roast = KitchenDish(id: "r", name: "Ente", source: .manual,
                                    tasks: [KitchenTask(id: "a", name: "Braten", component: "Ente", hands: 5,
                                                        unattended: 50, station: .oven)])

    @Test("Facets read duration, budget, equipment, hands and origin")
    func readFacets() throws {
        let saladFacets = try facets(salad)
        #expect(saladFacets.duration == .quick && saladFacets.fitsBudget)
        #expect(saladFacets.equipment == .noHeat && saladFacets.origin == .imported)
        #expect(saladFacets.handsShare == 1)
        let roastFacets = try facets(roast)
        #expect(roastFacets.duration == .long && !roastFacets.fitsBudget)
        #expect(roastFacets.equipment == .oven && roastFacets.origin == .own)
        #expect(roastFacets.handsShare < 0.2)
    }

    @Test("Every set facet must match")
    func filter() throws {
        let saladFacets = try facets(salad), roastFacets = try facets(roast)
        #expect(KitchenDishCollection.fits.filter.matches(saladFacets, history: .none))
        #expect(!KitchenDishCollection.fits.filter.matches(roastFacets, history: .none))
        #expect(KitchenDishFilter(lowWorkOnly: true).matches(roastFacets, history: .none))
        #expect(!KitchenDishFilter(equipment: .oven, origin: .imported).matches(roastFacets, history: .none))
        #expect(!KitchenDishFilter().isActive && KitchenDishFilter(history: .never).isActive)
    }

    @Test("History: never, long ago and favourites from the records")
    func history() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func run(_ daysAgo: Double, rating: Int?) -> KitchenCookRun {
            var run = KitchenCookRun(dishID: "r", dishName: "Ente", startedAt: now.addingTimeInterval(-daysAgo * 86_400),
                                     totalSeconds: 3000, plannedMinutes: 55, steps: [])
            run.rating = rating
            return run
        }
        let history = KitchenDishFilter.History(dishID: "r", runs: [run(90, rating: 5), run(70, rating: 4), run(1, rating: nil)])
        #expect(history.count == 3 && history.rating == 4.5)
        let facets = KitchenDishFacets(dish: roast, schedule: (try? KitchenScheduler.schedule(roast.tasks, kitchen: Kitchen(), budget: 60))!)
        #expect(KitchenDishFilter(history: .favourites).matches(facets, history: history, now: now))
        #expect(!KitchenDishFilter(history: .longAgo).matches(facets, history: history, now: now))
        #expect(!KitchenDishFilter(history: .never).matches(facets, history: history, now: now))
        #expect(KitchenDishFilter(history: .longAgo).matches(facets, history: .none, now: now))
    }

    @Test("Search finds name, component and ingredient, without case or accents")
    func search() {
        #expect(KitchenDishFilter.matches(salad, searchText: "ziegenkase"))
        #expect(KitchenDishFilter.matches(salad, searchText: "feldsalat"))
        #expect(KitchenDishFilter.matches(roast, searchText: ""))
        #expect(!KitchenDishFilter.matches(roast, searchText: "Fisch"))
    }

    @Test("A saved filter with an unknown facet still reads")
    func decoding() throws {
        let json = #"{"duration":"quick","spiciness":"hot","history":"someday"}"#
        let filter = try JSONDecoder().decode(KitchenDishFilter.self, from: Data(json.utf8))
        #expect(filter == KitchenDishFilter(duration: .quick))
    }
}
