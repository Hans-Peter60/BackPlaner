//
//  InMemoryRecipeStore.swift
//  BakePlannerCore
//
//  A RecipeStore that keeps everything in memory: the reference the
//  contract is checked against first, and a stand-in for tests that need a
//  store but not its persistence.
//

import Foundation

public final class InMemoryRecipeStore: RecipeStore {
    private var stored: [String: StoredRecipe] = [:]
    private var nextID = 1

    public init() {}

    public func recipes(includingImages: Bool) throws -> [StoredRecipe] {
        stored.values
            .map { recipe in
                var recipe = recipe
                if !includingImages { recipe.content.image = nil }
                return recipe
            }
            .sorted { $0.content.name.localizedStandardCompare($1.content.name) == .orderedAscending }
    }

    public func recipe(id: String) throws -> StoredRecipe? {
        stored[id]
    }

    public func recipe(firestoreId: String) throws -> StoredRecipe? {
        stored.values.first { $0.firestoreId == firestoreId }
    }

    public func add(_ content: RecipeExportData, firestoreId: String?, adjustedOn: Date?,
                    bakeHistoryFlag: Bool) throws -> StoredRecipe {
        let recipe = StoredRecipe(id: "memory-\(nextID)", firestoreId: firestoreId, adjustedOn: adjustedOn,
                                  bakeHistoryFlag: bakeHistoryFlag, content: content.inStoreOrder)
        nextID += 1
        stored[recipe.id] = recipe
        return recipe
    }

    public func update(_ recipe: StoredRecipe) throws {
        guard let existing = stored[recipe.id] else { throw RecipeStoreError.unknownRecipe(recipe.id) }
        var updated = recipe
        updated.content = recipe.content.inStoreOrder
        updated.content.image = existing.content.image
        stored[recipe.id] = updated
    }

    public func setImage(_ image: Data?, forRecipe id: String) throws {
        guard stored[id] != nil else { throw RecipeStoreError.unknownRecipe(id) }
        stored[id]?.content.image = image
    }

    public func delete(id: String) throws {
        stored[id] = nil
    }
}
