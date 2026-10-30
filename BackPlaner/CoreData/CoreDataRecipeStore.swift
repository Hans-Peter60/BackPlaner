//
//  CoreDataRecipeStore.swift
//  BackPlaner
//
//  The user's own recipes kept in Core Data (and iCloud) — the iOS side of
//  RecipeStore. A recipe's key is its object ID: older recipes may have no
//  UUID, and assigning one on reading would write to iCloud.
//

import BakePlannerCore
import CoreData
import Foundation

struct CoreDataRecipeStore: RecipeStore {

    let context: NSManagedObjectContext

    func recipes(includingImages: Bool) throws -> [StoredRecipe] {
        try context.fetch(Recipe.fetchRequest())
            .map { stored($0, includingImage: includingImages) }
            .sorted { $0.content.name.localizedStandardCompare($1.content.name) == .orderedAscending }
    }

    func recipe(id: String) throws -> StoredRecipe? {
        managedRecipe(id: id).map { stored($0, includingImage: true) }
    }

    func recipe(firestoreId: String) throws -> StoredRecipe? {
        let request = Recipe.fetchRequest()
        request.predicate = NSPredicate(format: "firestoreId == %@", firestoreId)
        request.fetchLimit = 1
        return try context.fetch(request).first.map { stored($0, includingImage: true) }
    }

    func add(_ content: RecipeExportData, firestoreId: String?, adjustedOn: Date?,
             bakeHistoryFlag: Bool) throws -> StoredRecipe {
        let recipe = content.makeRecipe(in: context)
        recipe.firestoreId = firestoreId
        recipe.adjustedOn = adjustedOn
        recipe.bakeHistoryFlag = bakeHistoryFlag
        try save()
        return stored(recipe, includingImage: true)
    }

    func update(_ updated: StoredRecipe) throws {
        guard let recipe = managedRecipe(id: updated.id) else {
            throw RecipeStoreError.unknownRecipe(updated.id)
        }
        let content = updated.content.inStoreOrder
        let current = RecipeExportData(recipe: recipe, includingImage: false)

        recipe.name                   = content.name
        recipe.summary                = content.summary
        recipe.urlLink                = content.urlLink
        recipe.prepTime               = content.prepTime
        recipe.totalWeight            = content.totalWeight
        recipe.tags                   = content.tags
        recipe.rating                 = content.rating
        recipe.recurrenceIntervalDays = content.recurrenceIntervalDays
        recipe.firestoreId            = updated.firestoreId
        recipe.adjustedOn             = updated.adjustedOn
        recipe.bakeHistoryFlag        = updated.bakeHistoryFlag

        // Components and steps are rebuilt only when they changed: their
        // objects carry nothing else, but rewriting them for a new name
        // would send every one of them through iCloud again.
        if content.components != current.components {
            recipe.replaceComponents(with: content.components, in: context)
        }
        if content.instructions != current.instructions {
            recipe.replaceInstructions(with: content.instructions, in: context)
        }
        try save()
    }

    func setImage(_ image: Data?, forRecipe id: String) throws {
        guard let recipe = managedRecipe(id: id) else { throw RecipeStoreError.unknownRecipe(id) }
        recipe.image = image ?? Data()
        try save()
    }

    func delete(id: String) throws {
        guard let recipe = managedRecipe(id: id) else { return }
        context.delete(recipe)
        try save()
    }

    // MARK: Helpers

    private func stored(_ recipe: Recipe, includingImage: Bool) -> StoredRecipe {
        StoredRecipe(id: recipe.objectID.uriRepresentation().absoluteString,
                     firestoreId: recipe.firestoreId,
                     adjustedOn: recipe.adjustedOn,
                     bakeHistoryFlag: recipe.bakeHistoryFlag,
                     content: RecipeExportData(recipe: recipe, includingImage: includingImage))
    }

    private func managedRecipe(id: String) -> Recipe? {
        // Core Data raises an Objective-C exception, which Swift cannot
        // catch, for a key that is not one of its own URIs at all.
        guard let url = URL(string: id), url.scheme == "x-coredata", url.host() != nil,
              let objectID = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
              let recipe = try? context.existingObject(with: objectID) as? Recipe,
              !recipe.isDeleted else { return nil }
        return recipe
    }

    private func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}
