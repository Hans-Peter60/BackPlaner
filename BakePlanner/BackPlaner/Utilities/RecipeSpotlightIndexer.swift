//
//  RecipeSpotlightIndexer.swift
//  BackPlaner
//
//  Keeps the user's own recipes in the app's Spotlight index as
//  RecipeEntity items: all of them once per launch, and again whenever a
//  recipe is saved, deleted or arrives from iCloud. Recipes that are gone
//  leave the index too; the ids indexed last time are kept in UserDefaults
//  for that. Saves come in bursts (an import writes every ingredient), so
//  the pass runs two seconds after the last one.
//

import BakePlannerCore
import CoreData
import CoreSpotlight
import Foundation

@MainActor
final class RecipeSpotlightIndexer {

    static let shared = RecipeSpotlightIndexer()

    /// A named index, as Apple asks for in production; the default index
    /// is meant for prototyping.
    static let indexName = "BakePlannerRecipes"
    private static let indexedIDsKey = "spotlight.indexedRecipeIDs"

    private var container: NSPersistentContainer?
    private var observers: [NSObjectProtocol] = []
    private var pendingPass: Task<Void, Never>?

    private init() {}

    /// Starts listening for saves and remote changes of `container` and
    /// indexes every recipe right away.
    func start(with container: NSPersistentContainer) {
        guard self.container == nil else { return }
        self.container = container

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSManagedObjectContextDidSave, object: nil, queue: nil) {
            [weak self] (notification: Foundation.Notification) in
            guard let context = notification.object as? NSManagedObjectContext,
                  context.persistentStoreCoordinator === container.persistentStoreCoordinator,
                  Self.touchesRecipes(notification) else { return }
            Task { @MainActor [weak self] in self?.schedulePass() }
        })
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange,
                                            object: container.persistentStoreCoordinator, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in self?.schedulePass() }
        })

        schedulePass()
    }

    // `Foundation.` spelled out: the app has a `Notification` struct of its
    // own for reminders, which would shadow this one.
    private static func touchesRecipes(_ notification: Foundation.Notification) -> Bool {
        for key in [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey] {
            if let objects = notification.userInfo?[key] as? Set<NSManagedObject>,
               objects.contains(where: { $0 is Recipe }) {
                return true
            }
        }
        return false
    }

    private func schedulePass() {
        pendingPass?.cancel()
        pendingPass = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            do {
                try await self?.indexAll()
            } catch {
                AppLog.persistence.error("Spotlight: recipes could not be indexed: \(error)")
            }
        }
    }

    /// Every recipe into the index, recipes that are gone out of it.
    func indexAll() async throws {
        let recipes = try RecipeLookup.recipes()
        let entities = recipes.map(RecipeEntity.init)
        let index = CSSearchableIndex(name: Self.indexName)

        let current = Set(entities.map(\.id))
        let previous = Set(UserDefaults.standard.stringArray(forKey: Self.indexedIDsKey) ?? [])
        let gone = Array(previous.subtracting(current))
        if !gone.isEmpty {
            try await index.deleteAppEntities(identifiedBy: gone, ofType: RecipeEntity.self)
        }
        if !entities.isEmpty {
            try await index.indexAppEntities(entities)
        }
        UserDefaults.standard.set(Array(current), forKey: Self.indexedIDsKey)
        AppLog.persistence.info("Spotlight: \(entities.count) recipes indexed, \(gone.count) removed")
    }

    /// The recipes with these ids again — the system's partial reindex.
    func index(recipeIDs: [String]) async throws {
        let entities = try RecipeLookup.recipes().filter { recipeIDs.contains($0.reminderId) }.map(RecipeEntity.init)
        guard !entities.isEmpty else { return }
        try await CSSearchableIndex(name: Self.indexName).indexAppEntities(entities)
    }
}
