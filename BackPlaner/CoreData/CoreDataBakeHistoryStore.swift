//
//  CoreDataBakeHistoryStore.swift
//  BackPlaner
//
//  The bake history kept in Core Data (and iCloud) — the iOS side of
//  BakeHistoryStore. Keys are object IDs: entries written when a bake is
//  planned carry no UUID.
//

import BakePlannerCore
import CoreData
import Foundation

struct CoreDataBakeHistoryStore: BakeHistoryStore {

    let context: NSManagedObjectContext

    func entries(includingImages: Bool) throws -> [StoredBakeHistory] {
        let request = BakeHistory.fetchRequest()
        // As the history screen has it: an entry without a recipe is left
        // over from older versions and belongs to nothing.
        request.predicate = NSPredicate(format: "recipe != nil")
        return try context.fetch(request)
            .compactMap { stored($0, includingImages: includingImages) }
            .sorted(by: Self.newestFirst)
    }

    func entries(ofRecipe recipeID: String, includingImages: Bool) throws -> [StoredBakeHistory] {
        guard let recipe: Recipe = context.existingObject(storeKey: recipeID) else { return [] }
        return recipe.bakeHistoriesArray
            .compactMap { stored($0, includingImages: includingImages) }
            .sorted(by: Self.newestFirst)
    }

    func entry(id: String) throws -> StoredBakeHistory? {
        managedEntry(id: id).flatMap { stored($0, includingImages: true) }
    }

    func add(toRecipe recipeID: String, date: Date, comment: String, images: [Data],
             facts: BakeHistoryFacts) throws -> StoredBakeHistory {
        guard let recipe: Recipe = context.existingObject(storeKey: recipeID) else {
            throw BakeHistoryStoreError.unknownRecipe(recipeID)
        }
        let history = BakeHistory(context: context)
        history.id = UUID()
        history.date = date
        history.comment = comment
        history.images = images.isEmpty ? nil : images
        history.facts = facts
        recipe.bakeHistoryFlag = true
        recipe.addToBakeHistories(history)
        try save()
        guard let entry = stored(history, includingImages: true) else {
            throw BakeHistoryStoreError.unknownRecipe(recipeID)
        }
        return entry
    }

    func update(_ entry: StoredBakeHistory) throws {
        guard let history = managedEntry(id: entry.id) else { throw BakeHistoryStoreError.unknownEntry(entry.id) }
        // Assigned only where something changed: photos are heavy, and an
        // unchanged entry need not go through iCloud again.
        if Self.date(of: history) != entry.date { history.date = entry.date }
        if Self.comment(of: history) != entry.comment { history.comment = entry.comment }
        if (history.images ?? []) != entry.images { history.images = entry.images.isEmpty ? nil : entry.images }
        if history.facts != entry.facts.normalized { history.facts = entry.facts }
        try save()
    }

    func delete(id: String) throws {
        guard let history = managedEntry(id: id) else { return }
        context.delete(history)
        try save()
    }

    // MARK: Helpers

    private static func newestFirst(_ first: StoredBakeHistory, _ second: StoredBakeHistory) -> Bool {
        first.date != second.date ? first.date > second.date : first.id < second.id
    }

    /// The entry as the store hands it out; nil for one without a recipe.
    private func stored(_ history: BakeHistory, includingImages: Bool) -> StoredBakeHistory? {
        guard let recipe = history.recipe, !recipe.isDeleted else { return nil }
        return StoredBakeHistory(id: history.storeKey,
                                 recipeID: recipe.storeKey,
                                 date: Self.date(of: history),
                                 comment: Self.comment(of: history),
                                 images: includingImages ? (history.images ?? []) : [],
                                 facts: history.facts)
    }

    private func managedEntry(id: String) -> BakeHistory? {
        guard let history: BakeHistory = context.existingObject(storeKey: id),
              history.recipe.map({ !$0.isDeleted }) == true else { return nil }
        return history
    }

    // Date and comment are optional in the model, though not in the Swift
    // class: read so that a missing value cannot crash.
    private static func date(of history: BakeHistory) -> Date {
        history.value(forKey: "date") as? Date ?? .distantPast
    }

    private static func comment(of history: BakeHistory) -> String {
        history.value(forKey: "comment") as? String ?? ""
    }

    private func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}
