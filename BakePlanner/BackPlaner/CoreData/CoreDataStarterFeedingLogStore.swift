//
//  CoreDataStarterFeedingLogStore.swift
//  BackPlaner
//
//  The starter feeding diary kept in Core Data (and iCloud) — the iOS side
//  of StarterFeedingLogStore. Keys are object IDs, like those of the other
//  Core Data stores.
//

import BakePlannerCore
import CoreData
import Foundation

struct CoreDataStarterFeedingLogStore: StarterFeedingLogStore {

    let context: NSManagedObjectContext

    func feedings(ofRecipe recipeID: String) throws -> [StoredStarterFeeding] {
        guard let recipe: Recipe = context.existingObject(storeKey: recipeID) else { return [] }
        return recipe.starterFeedingLogsArray
            .map { stored($0, recipe: recipe) }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
    }

    func add(toRecipe recipeID: String, date: Date, facts: StarterFeedingFacts) throws -> StoredStarterFeeding {
        guard let recipe: Recipe = context.existingObject(storeKey: recipeID) else {
            throw StarterFeedingLogStoreError.unknownRecipe(recipeID)
        }
        let feeding = StarterFeedingLog(context: context)
        feeding.id = UUID()
        feeding.date = date
        feeding.facts = facts
        recipe.addToStarterFeedingLogs(feeding)
        try save()
        return stored(feeding, recipe: recipe)
    }

    func update(_ updated: StoredStarterFeeding) throws {
        guard let feeding = managedFeeding(id: updated.id) else {
            throw StarterFeedingLogStoreError.unknownFeeding(updated.id)
        }
        if feeding.facts != updated.facts.normalized {
            feeding.facts = updated.facts
        }
        try save()
    }

    func delete(id: String) throws {
        guard let feeding = managedFeeding(id: id) else { return }
        context.delete(feeding)
        try save()
    }

    private func managedFeeding(id: String) -> StarterFeedingLog? {
        guard let feeding: StarterFeedingLog = context.existingObject(storeKey: id),
              feeding.recipe.map({ !$0.isDeleted }) == true else { return nil }
        return feeding
    }

    // MARK: Helpers

    private func stored(_ feeding: StarterFeedingLog, recipe: Recipe) -> StoredStarterFeeding {
        // The date is optional in the model, though not in the Swift class:
        // read so that a missing value cannot crash.
        StoredStarterFeeding(id: feeding.storeKey,
                             recipeID: recipe.storeKey,
                             date: feeding.value(forKey: "date") as? Date ?? .distantPast,
                             facts: feeding.facts)
    }

    private func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}
