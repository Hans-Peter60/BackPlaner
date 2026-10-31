//
//  BakeHistoryStoreContract.swift
//  BakePlannerCore
//
//  What every BakeHistoryStore must do, written once and checked against
//  each store: in memory, Core Data, SQLite. Each check takes a new, empty
//  bake history store and the recipe store kept beside it, and throws
//  ContractViolation when the store behaves differently.
//

import Foundation

public enum BakeHistoryStoreContract {

    public typealias Check = (BakeHistoryStore, RecipeStore) throws -> Void

    /// Every check by name, for running them one by one.
    public static let checks: [(name: String, run: Check)] = [
        ("an empty store has nothing", emptyStore),
        ("an entry comes back as it was added, and marks its recipe", addAndRead),
        ("facts are kept normalized", normalizedFacts),
        ("entries come newest first, photos only when asked", order),
        ("an update changes everything but the recipe", update),
        ("a removed entry is gone, the others stay", delete),
        ("removing a recipe removes its entries", recipeRemoved),
        ("unknown keys are reported, not ignored", unknownKeys),
    ]

    // MARK: Checks

    public static func emptyStore(_ store: BakeHistoryStore, _ recipes: RecipeStore) throws {
        try expect(store.entries(includingImages: true).isEmpty, "an empty store lists entries")
        try expect(store.entry(id: "none") == nil, "an empty store finds an entry by key")
        try expect(store.entries(ofRecipe: "none", includingImages: true).isEmpty,
                   "an empty store finds entries of an unknown recipe")
    }

    public static func addAndRead(_ store: BakeHistoryStore, _ recipes: RecipeStore) throws {
        let bread = try newRecipe(recipes)
        try expect(!bread.bakeHistoryFlag, "a new recipe counts as baked")

        let added = try store.add(toRecipe: bread.id, date: day(10), comment: "Schöne Kruste – „offen“",
                                  images: photos(), facts: facts())

        try expect(!added.id.isEmpty, "the new entry has no key")
        try expect(added.recipeID == bread.id && added.date == day(10) && added.comment == "Schöne Kruste – „offen“"
                   && added.images == photos() && added.facts == facts(),
                   "add returns other content than it was given")
        try expect(store.entry(id: added.id) == added, "the entry read by key differs from the one added")
        try expect(store.entries(includingImages: true) == [added], "the store lists other entries")
        try expect(store.entries(ofRecipe: bread.id, includingImages: true) == [added],
                   "the recipe's entries differ")
        try expect(recipes.recipe(id: bread.id)?.bakeHistoryFlag == true, "the recipe is not marked as baked")
    }

    public static func normalizedFacts(_ store: BakeHistoryStore, _ recipes: RecipeStore) throws {
        let bread = try newRecipe(recipes)
        let raw = BakeHistoryFacts(roomTemperature: 0, doughTemperature: nil, bulkProofMinutes: 0,
                                   finalProofMinutes: -5, flour: "  Weizen 550 ", outcome: " \n")
        let added = try store.add(toRecipe: bread.id, date: day(10), comment: "", images: [], facts: raw)

        let expected = BakeHistoryFacts(roomTemperature: 0, flour: "Weizen 550")
        try expect(added.facts == expected, "add does not normalize the facts: \(added.facts)")
        try expect(store.entry(id: added.id)?.facts == expected, "the stored facts are not normalized")

        var changed = added
        changed.facts.outcome = " offen "
        changed.facts.bulkProofMinutes = 0
        try store.update(changed)
        try expect(store.entry(id: added.id)?.facts == BakeHistoryFacts(roomTemperature: 0, flour: "Weizen 550",
                                                                       outcome: "offen"),
                   "update does not normalize the facts")
    }

    public static func order(_ store: BakeHistoryStore, _ recipes: RecipeStore) throws {
        let bread = try newRecipe(recipes)
        let zopf = try newRecipe(recipes, name: "Zopf")
        let middle = try store.add(toRecipe: bread.id, date: day(12), comment: "", images: photos(), facts: facts())
        let oldest = try store.add(toRecipe: zopf.id, date: day(10), comment: "", images: photos(), facts: facts())
        let newest = try store.add(toRecipe: bread.id, date: day(14), comment: "", images: [], facts: facts())

        let withImages = try store.entries(includingImages: true)
        try expect(withImages.map(\.id) == [newest.id, middle.id, oldest.id], "the entries are not newest first")
        try expect(withImages == [newest, middle, oldest], "the listed entries differ from the ones added")
        let withoutImages = try store.entries(includingImages: false)
        try expect(withoutImages.map(\.id) == withImages.map(\.id) && withoutImages.allSatisfy { $0.images.isEmpty },
                   "the list without photos has them, or other entries")
        try expect(store.entries(ofRecipe: bread.id, includingImages: true) == [newest, middle],
                   "the recipe's entries are not its own, newest first")
        try expect(store.entries(ofRecipe: zopf.id, includingImages: false).map(\.id) == [oldest.id],
                   "the other recipe's entries are not its own")
        try expect(store.entry(id: middle.id)?.images == photos(), "the entry read by key lacks its photos")
    }

    public static func update(_ store: BakeHistoryStore, _ recipes: RecipeStore) throws {
        let bread = try newRecipe(recipes)
        let zopf = try newRecipe(recipes, name: "Zopf")
        let added = try store.add(toRecipe: bread.id, date: day(10), comment: "Gut", images: photos(), facts: facts())
        let other = try store.add(toRecipe: bread.id, date: day(11), comment: "", images: [], facts: BakeHistoryFacts())

        var changed = added
        changed.date = day(20)
        changed.comment = ""
        changed.images = [Data([0x0D])]
        changed.facts = BakeHistoryFacts(doughTemperature: 26.5, finalProofMinutes: 45)
        changed.recipeID = zopf.id
        try store.update(changed)

        var expected = changed
        expected.recipeID = bread.id
        try expect(store.entry(id: added.id) == expected, "the updated entry differs from the update")
        try expect(store.entry(id: other.id) == other, "the update changed another entry")
        try expect(store.entries(ofRecipe: zopf.id, includingImages: false).isEmpty, "the update moved the entry")

        changed.images = []
        try store.update(changed)
        try expect(store.entry(id: added.id)?.images == [], "the photos were not removed")
    }

    public static func delete(_ store: BakeHistoryStore, _ recipes: RecipeStore) throws {
        let bread = try newRecipe(recipes)
        let first = try store.add(toRecipe: bread.id, date: day(10), comment: "", images: photos(), facts: facts())
        let second = try store.add(toRecipe: bread.id, date: day(11), comment: "", images: [], facts: facts())

        try store.delete(id: first.id)
        try expect(store.entry(id: first.id) == nil, "the removed entry is still there")
        try expect(store.entries(includingImages: true) == [second], "the other entry went too")
        try expect(recipes.recipe(id: bread.id) != nil, "removing an entry removed its recipe")
        try store.delete(id: first.id)
    }

    public static func recipeRemoved(_ store: BakeHistoryStore, _ recipes: RecipeStore) throws {
        let bread = try newRecipe(recipes)
        let zopf = try newRecipe(recipes, name: "Zopf")
        let gone = try store.add(toRecipe: bread.id, date: day(10), comment: "", images: photos(), facts: facts())
        let kept = try store.add(toRecipe: zopf.id, date: day(11), comment: "", images: [], facts: facts())

        try recipes.delete(id: bread.id)

        try expect(store.entry(id: gone.id) == nil, "an entry of the removed recipe is still there")
        try expect(store.entries(includingImages: true) == [kept], "the other recipe's entry went too, or more stayed")
        try expect(store.entries(ofRecipe: bread.id, includingImages: true).isEmpty,
                   "the removed recipe still has entries")
    }

    public static func unknownKeys(_ store: BakeHistoryStore, _ recipes: RecipeStore) throws {
        do {
            _ = try store.add(toRecipe: "none", date: day(10), comment: "", images: [], facts: facts())
            throw ContractViolation(description: "adding an entry to an unknown recipe did not fail")
        } catch BakeHistoryStoreError.unknownRecipe {}
        do {
            try store.update(StoredBakeHistory(id: "none", recipeID: "none", date: day(10)))
            throw ContractViolation(description: "updating an unknown entry did not fail")
        } catch BakeHistoryStoreError.unknownEntry {}
        try store.delete(id: "none")
        try expect(store.entries(includingImages: true).isEmpty, "an unknown key created an entry")
    }

    // MARK: Helpers

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw ContractViolation(description: message()) }
    }

    private static func newRecipe(_ recipes: RecipeStore, name: String = "Landbrot") throws -> StoredRecipe {
        var content = RecipeStoreContract.bread()
        content.name = name
        return try recipes.add(content, firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
    }

    /// A moment in November 2026, on whole seconds.
    private static func day(_ day: Int) -> Date {
        Date(timeIntervalSince1970: 1_793_520_000 + Double(day) * 86_400)
    }

    private static func photos() -> [Data] {
        [Data([0x0A, 0x0B, 0x0C]), Data([0x0E])]
    }

    private static func facts() -> BakeHistoryFacts {
        BakeHistoryFacts(roomTemperature: 22, doughTemperature: 25.5, bulkProofMinutes: 210, finalProofMinutes: 60,
                         flour: "Weizen 550, Drax-Mühle", outcome: "offen, gute Ofenfeder")
    }
}
