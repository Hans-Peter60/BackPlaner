//
//  ShoppingListStoreContract.swift
//  BakePlannerCore
//
//  What every ShoppingListStore must do, written once and checked against
//  each store: in memory, Core Data, SQLite. Each check takes a new, empty
//  shopping list store and the recipe store kept beside it, and throws
//  ContractViolation when the store behaves differently.
//
//  Amounts are in grams or units without conversion, so the checks give
//  the same result with or without the unit table.
//

import Foundation

public enum ShoppingListStoreContract {

    public typealias Check = (ShoppingListStore, RecipeStore) throws -> Void

    /// Every check by name, for running them one by one.
    public static let checks: [(name: String, run: Check)] = [
        ("an empty store has nothing", emptyStore),
        ("a new list is empty and comes back as it was added", newList),
        ("lists are ordered by date, the latest of a day is found", listsByDate),
        ("lines come back as applied, ordered by name", applyLines),
        ("applying keeps, changes, adds and removes lines", applyKeepsKeys),
        ("recipes are recorded once each", recipesRecorded),
        ("a deleted recipe drops out, its ingredients stay", deletedRecipe),
        ("a line is updated on its own", updateItem),
        ("lines and lists are removed, recipes stay", deleteItemAndList),
        ("a recipe added twice adds up on the same lines", addRecipe),
        ("unknown keys are reported, not ignored", unknownKeys),
    ]

    // MARK: Checks

    public static func emptyStore(_ store: ShoppingListStore, _ recipes: RecipeStore) throws {
        try expect(store.lists().isEmpty, "an empty store lists shopping lists")
        try expect(store.list(id: "none") == nil, "an empty store finds a list by key")
    }

    public static func newList(_ store: ShoppingListStore, _ recipes: RecipeStore) throws {
        let added = try store.addList(on: day(10, hour: 9))

        try expect(!added.id.isEmpty, "the new list has no key")
        try expect(added.date == day(10, hour: 9), "the new list has another date")
        try expect(added.items.isEmpty && added.recipeIDs.isEmpty && added.publicRecipeNames.isEmpty
                   && added.recipeNames.isEmpty, "the new list is not empty")
        try expect(store.list(id: added.id) == added, "the list read by key differs from the one added")
        try expect(store.lists() == [added], "the store lists other lists than the one added")
    }

    public static func listsByDate(_ store: ShoppingListStore, _ recipes: RecipeStore) throws {
        let late = try store.addList(on: day(12, hour: 18))
        let early = try store.addList(on: day(10, hour: 9))
        let morning = try store.addList(on: day(12, hour: 8))

        try expect(store.lists().map(\.id) == [early.id, morning.id, late.id], "the lists are not ordered by date")
        try expect(store.list(onSameDayAs: day(12, hour: 12), calendar: utc)?.id == late.id,
                   "the latest list of the day is not the one found")
        try expect(store.list(onSameDayAs: day(11, hour: 12), calendar: utc) == nil,
                   "a list is found for a day without one")
    }

    public static func applyLines(_ store: ShoppingListStore, _ recipes: RecipeStore) throws {
        let list = try store.addList(on: day(10, hour: 9))
        try store.apply(sampleLines(), recipe: nil, toList: list.id)

        let items = try store.list(id: list.id)?.items ?? []
        try expect(items.map(\.name) == ["Butter", "Hefe", "Weizenmehl 550"],
                   "the lines are not ordered by name: \(items.map(\.name))")
        try expect(items.map { $0.line.withoutKey } == sampleLines().sorted { $0.name < $1.name },
                   "the lines read back differ from the ones applied")
        try expect(items.allSatisfy { !$0.id.isEmpty } && Set(items.map(\.id)).count == 3,
                   "the lines have no keys of their own")
        try expect(store.lists().first?.items == items, "the list in the overview has other lines")
    }

    public static func applyKeepsKeys(_ store: ShoppingListStore, _ recipes: RecipeStore) throws {
        let list = try store.addList(on: day(10, hour: 9))
        try store.apply(sampleLines(), recipe: nil, toList: list.id)
        let before = try store.list(id: list.id)?.items ?? []
        guard let flour = before.first(where: { $0.name == "Weizenmehl 550" }),
              let butter = before.first(where: { $0.name == "Butter" }) else {
            throw ContractViolation(description: "the applied lines are missing")
        }

        var moreFlour = flour.line
        moreFlour.weight = 750
        moreFlour.normWeight = 750
        let sugar = ShoppingListLine(name: "Zucker", unit: "g", weight: 50, normWeight: 50, num: 0, denom: 0)
        // Hefe left out: removed.
        try store.apply([butter.line, moreFlour, sugar], recipe: nil, toList: list.id)

        let after = try store.list(id: list.id)?.items ?? []
        try expect(after.map(\.name) == ["Butter", "Weizenmehl 550", "Zucker"],
                   "the lines after applying again are \(after.map(\.name))")
        try expect(after[0] == butter, "an unchanged line changed")
        try expect(after[1].id == flour.id && after[1].weight == 750 && after[1].normWeight == 750,
                   "a changed line lost its key or its amount")
        try expect(!after[2].id.isEmpty && after[2].id != flour.id && after[2].id != butter.id,
                   "the new line has no key of its own")
        try expect(after[2].line.withoutKey == sugar, "the new line differs from the one applied")
    }

    public static func recipesRecorded(_ store: ShoppingListStore, _ recipes: RecipeStore) throws {
        let bread = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        let list = try store.addList(on: day(10, hour: 9))

        try store.apply([], recipe: .own(id: bread.id), toList: list.id)
        try store.apply([], recipe: .own(id: bread.id), toList: list.id)
        try store.apply([], recipe: .publicRecipe(name: " Zopf "), toList: list.id)
        try store.apply([], recipe: .publicRecipe(name: "Zopf"), toList: list.id)
        try store.apply([], recipe: .publicRecipe(name: "  "), toList: list.id)
        try store.apply([], recipe: .publicRecipe(name: "Apfelkuchen"), toList: list.id)

        let read = try store.list(id: list.id)
        try expect(read?.recipeIDs == [bread.id], "the own recipe is not recorded once: \(read?.recipeIDs ?? [])")
        try expect(read?.publicRecipeNames == ["Zopf", "Apfelkuchen"],
                   "the public recipes are not recorded once each: \(read?.publicRecipeNames ?? [])")
        try expect(read?.recipeNames == ["Apfelkuchen", "Landbrot", "Zopf"],
                   "the recipe names are not all there in order: \(read?.recipeNames ?? [])")
    }

    public static func deletedRecipe(_ store: ShoppingListStore, _ recipes: RecipeStore) throws {
        let bread = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        let list = try store.addList(on: day(10, hour: 9))
        try store.apply(sampleLines(), recipe: .own(id: bread.id), toList: list.id)

        try recipes.delete(id: bread.id)

        let read = try store.list(id: list.id)
        try expect(read?.recipeIDs.isEmpty == true && read?.recipeNames.isEmpty == true,
                   "the deleted recipe is still on the list")
        try expect(read?.items.count == 3, "the deleted recipe took the lines with it")
    }

    public static func updateItem(_ store: ShoppingListStore, _ recipes: RecipeStore) throws {
        let list = try store.addList(on: day(10, hour: 9))
        try store.apply(sampleLines(), recipe: nil, toList: list.id)
        let before = try store.list(id: list.id)?.items ?? []
        guard var yeast = before.first(where: { $0.name == "Hefe" }) else {
            throw ContractViolation(description: "the applied lines are missing")
        }

        yeast.unit = "g"
        yeast.weight = 21
        yeast.normWeight = 21
        yeast.num = 0
        yeast.denom = 0
        try store.update(yeast)

        let after = try store.list(id: list.id)?.items ?? []
        try expect(after.count == 3, "updating a line changed the number of lines")
        try expect(after.first { $0.id == yeast.id } == yeast, "the updated line differs from the update")
        try expect(after.filter { $0.id != yeast.id } == before.filter { $0.id != yeast.id },
                   "updating a line changed the others")
    }

    public static func deleteItemAndList(_ store: ShoppingListStore, _ recipes: RecipeStore) throws {
        let bread = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        let first = try store.addList(on: day(10, hour: 9))
        let second = try store.addList(on: day(11, hour: 9))
        try store.apply(sampleLines(), recipe: .own(id: bread.id), toList: first.id)
        try store.apply(sampleLines(), recipe: .own(id: bread.id), toList: second.id)

        let lines = try store.list(id: first.id)?.items ?? []
        guard let butter = lines.first(where: { $0.name == "Butter" }) else {
            throw ContractViolation(description: "the applied lines are missing")
        }
        try store.deleteItem(id: butter.id)
        try expect(store.list(id: first.id)?.items.map(\.name) == ["Hefe", "Weizenmehl 550"],
                   "the removed line is still there, or others went too")
        try expect(store.list(id: second.id)?.items.count == 3, "removing a line changed another list")
        try store.deleteItem(id: butter.id)

        try store.delete(id: first.id)
        try expect(store.list(id: first.id) == nil, "the removed list is still there")
        try expect(store.lists().map(\.id) == [second.id], "the other list went too")
        try expect(store.list(id: second.id)?.items.count == 3, "removing a list changed another one")
        try expect(recipes.recipe(id: bread.id) != nil, "removing a list removed its recipe")
        try store.delete(id: first.id)
    }

    public static func addRecipe(_ store: ShoppingListStore, _ recipes: RecipeStore) throws {
        let bread = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        let list = try store.addList(on: day(10, hour: 9))
        let entries = [ShoppingListEntry(name: "Weizenmehl 550", unit: "g", weight: 400, num: 0, denom: 0),
                       ShoppingListEntry(name: "Hefe", unit: "Würfel", weight: 0, num: 1, denom: 4)]

        try store.add(entries, from: .own(id: bread.id), toList: list.id)
        let once = try store.list(id: list.id)?.items ?? []
        try store.add(entries, from: .own(id: bread.id), toList: list.id)
        let twice = try store.list(id: list.id)?.items ?? []

        try expect(twice.map(\.id) == once.map(\.id), "adding the recipe again made new lines")
        try expect(twice.first { $0.name == "Weizenmehl 550" }?.weight == 800, "the flour did not add up")
        let yeast = twice.first { $0.name == "Hefe" }
        try expect(yeast?.num == 1 && yeast?.denom == 2, "the yeast did not add up to 1/2")
        try expect(store.list(id: list.id)?.recipeIDs == [bread.id], "the recipe is not recorded once")
    }

    public static func unknownKeys(_ store: ShoppingListStore, _ recipes: RecipeStore) throws {
        do {
            try store.apply(sampleLines(), recipe: nil, toList: "none")
            throw ContractViolation(description: "applying lines to an unknown list did not fail")
        } catch ShoppingListStoreError.unknownList {}
        do {
            try store.add([], from: .publicRecipe(name: "Zopf"), toList: "none")
            throw ContractViolation(description: "adding a recipe to an unknown list did not fail")
        } catch ShoppingListStoreError.unknownList {}
        do {
            try store.update(StoredShoppingListItem(id: "none", name: "Hefe", unit: "g", weight: 1, normWeight: 1,
                                                    num: 0, denom: 0))
            throw ContractViolation(description: "updating an unknown line did not fail")
        } catch ShoppingListStoreError.unknownItem {}

        let list = try store.addList(on: day(10, hour: 9))
        do {
            try store.apply(sampleLines(), recipe: .own(id: "none"), toList: list.id)
            throw ContractViolation(description: "recording an unknown own recipe did not fail")
        } catch ShoppingListStoreError.unknownRecipe {}
        try expect(store.list(id: list.id) == list, "a failed apply changed the list")

        let bread = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        try store.deleteItem(id: "none")
        try store.delete(id: "none")
        try expect(store.lists() == [list], "an unknown key changed the lists")
        try expect(recipes.recipe(id: bread.id) == bread, "an unknown key changed a recipe")
    }

    // MARK: Helpers

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw ContractViolation(description: message()) }
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// A moment in November 2026, UTC, on whole seconds.
    private static func day(_ day: Int, hour: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    /// Three lines with what a line can carry: grams, a fraction of a unit
    /// without a weight, no unit at all.
    private static func sampleLines() -> [ShoppingListLine] {
        [
            ShoppingListLine(name: "Weizenmehl 550", unit: "g", weight: 500, normWeight: 500, num: 0, denom: 0),
            ShoppingListLine(name: "Hefe", unit: "Würfel", weight: 0, normWeight: 10.5, num: 1, denom: 4),
            ShoppingListLine(name: "Butter", unit: nil, weight: 1, normWeight: 1, num: 0, denom: 0),
        ]
    }
}

private extension ShoppingListLine {
    var withoutKey: ShoppingListLine {
        var line = self
        line.key = nil
        return line
    }
}
