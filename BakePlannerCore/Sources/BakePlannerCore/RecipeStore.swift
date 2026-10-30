//
//  RecipeStore.swift
//  BakePlannerCore
//
//  The user's own recipes, wherever they are kept: Core Data with iCloud on
//  iOS, SQLite on Android. A recipe's content travels as RecipeExportData,
//  the same value the backup file holds, so moving between platforms needs
//  no other shape.
//

import Foundation

/// One of the user's own recipes as a store holds it.
public struct StoredRecipe: Equatable {
    /// The store's own key for the recipe. Stable for as long as the recipe
    /// exists; not meaningful on another device.
    public var id: String
    /// The public recipe this one is the own copy of, if any.
    public var firestoreId: String?
    /// When the recipe was last changed by a flour substitution or a starter
    /// adjustment; `nil` for one never adjusted.
    public var adjustedOn: Date?
    /// Whether the recipe has been baked or planned at least once.
    public var bakeHistoryFlag: Bool
    /// Name, ingredients, steps and picture.
    public var content: RecipeExportData

    public init(id: String, firestoreId: String? = nil, adjustedOn: Date? = nil,
                bakeHistoryFlag: Bool = false, content: RecipeExportData) {
        self.id = id
        self.firestoreId = firestoreId
        self.adjustedOn = adjustedOn
        self.bakeHistoryFlag = bakeHistoryFlag
        self.content = content
    }
}

/// Where the user's own recipes are kept.
///
/// Components come back ordered by `number`, their ingredients by `number`,
/// the steps by `step`. Lists are ordered by name as people read it
/// (`localizedStandardCompare`). The picture is heavy: lists leave it out
/// unless asked, and only `add` and `setImage` write it.
public protocol RecipeStore {
    /// Every recipe, ordered by name.
    func recipes(includingImages: Bool) throws -> [StoredRecipe]
    /// The recipe with this key, with its picture.
    func recipe(id: String) throws -> StoredRecipe?
    /// The own copy of the public recipe `firestoreId`, with its picture.
    func recipe(firestoreId: String) throws -> StoredRecipe?
    /// Keeps a new recipe, picture included, and returns it with its key.
    /// Never merges with an existing recipe of the same name.
    func add(_ content: RecipeExportData, firestoreId: String?, adjustedOn: Date?,
             bakeHistoryFlag: Bool) throws -> StoredRecipe
    /// Replaces everything of the recipe `recipe.id` but its picture.
    func update(_ recipe: StoredRecipe) throws
    /// Replaces the picture of the recipe `id`; `nil` removes it.
    func setImage(_ image: Data?, forRecipe id: String) throws
    /// Removes the recipe `id`. Nothing happens for an unknown key.
    func delete(id: String) throws
}

public enum RecipeStoreError: Error, Equatable {
    /// `update` or `setImage` for a key the store does not have.
    case unknownRecipe(String)
}

extension RecipeExportData {
    /// The content in the order every store returns it: components and their
    /// ingredients by number, steps by step.
    public var inStoreOrder: RecipeExportData {
        var ordered = self
        ordered.components = components
            .sorted { $0.number < $1.number }
            .map { component in
                var component = component
                component.ingredients = component.ingredients.sorted { $0.number < $1.number }
                return component
            }
        ordered.instructions = instructions.sorted { $0.step < $1.step }
        return ordered
    }
}
