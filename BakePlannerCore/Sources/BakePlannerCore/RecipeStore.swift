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
    /// The key of the recipe this one is a variant of — the recipe a flour
    /// substitution, a starter adjustment or "Variante anlegen" copied —
    /// nil for a recipe of its own. Removing the origin leaves the variant
    /// as a recipe of its own.
    public var originID: String?
    /// What the variant changes, in the baker's words; nil for none.
    public var variantNote: String?
    /// Name, ingredients, steps and picture.
    public var content: RecipeExportData

    public init(id: String, firestoreId: String? = nil, adjustedOn: Date? = nil,
                bakeHistoryFlag: Bool = false, originID: String? = nil, variantNote: String? = nil,
                content: RecipeExportData) {
        self.id = id
        self.firestoreId = firestoreId
        self.adjustedOn = adjustedOn
        self.bakeHistoryFlag = bakeHistoryFlag
        self.originID = originID
        self.variantNote = variantNote
        self.content = content
    }

    /// Whether the recipe is a variant of another one.
    public var isVariant: Bool { originID != nil }
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
    /// Keeps several new recipes at once, in the given order — all of them
    /// or, when keeping fails, none. What a backup file is read into.
    func add(contentsOf contents: [RecipeExportData]) throws -> [StoredRecipe]
    /// Replaces everything of the recipe `recipe.id` but its picture —
    /// origin and note included; an origin the store does not have is
    /// reported as `unknownRecipe`.
    func update(_ recipe: StoredRecipe) throws
    /// Replaces the picture of the recipe `id`; `nil` removes it.
    func setImage(_ image: Data?, forRecipe id: String) throws
    /// Removes the recipe `id`. Nothing happens for an unknown key.
    func delete(id: String) throws
}

public enum RecipeStoreError: Error, Equatable {
    /// `update` or `setImage` for a key the store does not have, or an
    /// origin it does not have.
    case unknownRecipe(String)
}

extension RecipeStore {
    /// Keeps a new recipe as a variant of `originID`, with `note` on what
    /// it changes. The content is kept as `add` keeps it; the origin and
    /// the note are set in the same breath.
    public func addVariant(_ content: RecipeExportData, of originID: String, note: String?,
                           adjustedOn: Date? = nil) throws -> StoredRecipe {
        guard try recipe(id: originID) != nil else { throw RecipeStoreError.unknownRecipe(originID) }
        var variant = try add(content, firestoreId: nil, adjustedOn: adjustedOn, bakeHistoryFlag: false)
        variant.originID = originID
        variant.variantNote = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        try update(variant)
        return try recipe(id: variant.id) ?? variant
    }

    /// The variants of recipe `originID`, by name.
    public func variants(of originID: String, includingImages: Bool = false) throws -> [StoredRecipe] {
        try recipes(includingImages: includingImages).filter { $0.originID == originID }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
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
