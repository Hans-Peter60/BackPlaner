//
//  StarterFeedingLogStore.swift
//  BakePlannerCore
//
//  The starter feeding diary, wherever it is kept: Core Data with iCloud on
//  iOS, SQLite on Android. Each feeding belongs to the recipe that feeds
//  the starter and goes when the recipe goes.
//

import Foundation

/// One feeding as a store holds it.
public struct StoredStarterFeeding: Equatable {
    /// The store's own key for the feeding.
    public var id: String
    /// The key of the starter's recipe, in the RecipeStore beside this store.
    public var recipeID: String
    public var date: Date
    /// Peak time, float test and note, as `StarterFeedingFacts.normalized`
    /// has them.
    public var facts: StarterFeedingFacts

    public init(id: String, recipeID: String, date: Date, facts: StarterFeedingFacts = StarterFeedingFacts()) {
        self.id = id
        self.recipeID = recipeID
        self.date = date
        self.facts = facts
    }
}

/// Where the starter feeding diary is kept, next to a RecipeStore on the
/// same storage. (`StarterFeedingStore` is taken by the iOS app's Siri
/// support.)
///
/// A feeding is recorded — by hand, or when a starter is planned, then
/// still without a result — and its result entered afterwards.
public protocol StarterFeedingLogStore {
    /// The feedings of recipe `recipeID`, newest first; none for an unknown
    /// recipe.
    func feedings(ofRecipe recipeID: String) throws -> [StoredStarterFeeding]
    /// Keeps a new feeding for recipe `recipeID`, its facts normalized.
    func add(toRecipe recipeID: String, date: Date, facts: StarterFeedingFacts) throws -> StoredStarterFeeding
    /// Replaces the result of feeding `feeding.id` — peak time, float test,
    /// note — normalized; its date and recipe stay.
    func update(_ feeding: StoredStarterFeeding) throws
    /// Removes the feeding. Nothing happens for an unknown key.
    func delete(id: String) throws
}

public enum StarterFeedingLogStoreError: Error, Equatable {
    case unknownFeeding(String)
    /// A recipe the RecipeStore beside this store does not have.
    case unknownRecipe(String)
}
