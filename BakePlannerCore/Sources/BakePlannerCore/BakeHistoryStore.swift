//
//  BakeHistoryStore.swift
//  BakePlannerCore
//
//  The record of the user's bakes, wherever it is kept: Core Data with
//  iCloud on iOS, SQLite on Android. Each entry belongs to one of the
//  user's own recipes and goes when the recipe goes.
//

import Foundation

/// One entry of the bake history as a store holds it.
public struct StoredBakeHistory: Equatable {
    /// The store's own key for the entry.
    public var id: String
    /// The key of the recipe baked, in the RecipeStore beside this store.
    public var recipeID: String
    /// When the bake ended (or, for a planned one, will end).
    public var date: Date
    public var comment: String
    /// Photos of the bake, JPEG, in the order they were added.
    public var images: [Data]
    /// Temperatures, proof times, flour and outcome, as
    /// `BakeHistoryFacts.normalized` has them.
    public var facts: BakeHistoryFacts

    public init(id: String, recipeID: String, date: Date, comment: String = "", images: [Data] = [],
                facts: BakeHistoryFacts = BakeHistoryFacts()) {
        self.id = id
        self.recipeID = recipeID
        self.date = date
        self.comment = comment
        self.images = images
        self.facts = facts
    }
}

/// Where the bake history is kept, next to a RecipeStore on the same
/// storage.
///
/// Entries come newest first. Photos are heavy: lists leave them out
/// unless asked.
public protocol BakeHistoryStore {
    /// Every entry of every recipe, newest first.
    func entries(includingImages: Bool) throws -> [StoredBakeHistory]
    /// The entries of recipe `recipeID`, newest first; none for an unknown
    /// recipe.
    func entries(ofRecipe recipeID: String, includingImages: Bool) throws -> [StoredBakeHistory]
    /// The entry with this key, with its photos.
    func entry(id: String) throws -> StoredBakeHistory?
    /// Keeps a new entry for recipe `recipeID` and marks the recipe as
    /// baked (`StoredRecipe.bakeHistoryFlag`). The facts are kept
    /// normalized.
    func add(toRecipe recipeID: String, date: Date, comment: String, images: [Data],
             facts: BakeHistoryFacts) throws -> StoredBakeHistory
    /// Replaces date, comment, photos and facts of entry `entry.id`; the
    /// recipe it belongs to stays.
    func update(_ entry: StoredBakeHistory) throws
    /// Removes the entry. Nothing happens for an unknown key.
    func delete(id: String) throws
}

public enum BakeHistoryStoreError: Error, Equatable {
    case unknownEntry(String)
    /// A recipe the RecipeStore beside this store does not have.
    case unknownRecipe(String)
}
