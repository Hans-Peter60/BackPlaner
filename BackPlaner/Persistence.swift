//
//  Persistence.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 08.02.24.
//

import CoreData
import CloudKit

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        return result
    }()

    let container: NSPersistentCloudKitContainer

    private static let cloudKitContainerIdentifier = "iCloud.de.hpm64625.BackPlaner"

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "BackPlaner")

        guard let storeDescription = container.persistentStoreDescriptions.first else {
            fatalError("Unable to find a persistent store description.")
        }

        if inMemory {
            storeDescription.url = URL(fileURLWithPath: "/dev/null")
            storeDescription.cloudKitContainerOptions = nil
        } else {
            storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerIdentifier
            )
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                Typical reasons for an error here include:
                * The parent directory does not exist, cannot be created, or disallows writing.
                * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                * The device is out of space.
                * The store could not be migrated to the current model version.
                Check the error message to determine what the actual problem was.
                */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
    }
}

// MARK: - One-time store maintenance

extension PersistenceController {

    private static let orphanCleanupKey = "maintenance.orphanCleanupV1"

    /// Removes objects that lost their owning recipe back when the model still
    /// used `Nullify` delete rules: deleting a recipe left its components,
    /// ingredients, instructions and bake histories behind. Those rows are
    /// invisible in the UI (the bake-history list filters on `recipe != nil`)
    /// but stay in the store — and in CloudKit — forever.
    ///
    /// Runs once per installation. The delete rules are `Cascade` now, so no new
    /// orphans appear and this never has to run again. If the pass fails it is
    /// retried on the next launch, since the flag is only set after a successful
    /// save.
    func cleanUpOrphanedObjectsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.orphanCleanupKey) else { return }

        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        context.perform {
            // Components first: deleting one now cascades into its ingredients,
            // so those need no pass of their own.
            var deleted = Self.deleteObjects(
                Component.fetchRequest(),
                where: "recipe == nil",
                in: context
            )
            deleted += Self.deleteObjects(
                Instruction.fetchRequest(),
                where: "recipe == nil",
                in: context
            )
            deleted += Self.deleteObjects(
                BakeHistory.fetchRequest(),
                where: "recipe == nil",
                in: context
            )
            // Ingredients whose component is already gone. Shopping-list
            // ingredients are deliberately component-less copies, so they may
            // only be removed when they belong to no shopping list either.
            deleted += Self.deleteObjects(
                Ingredient.fetchRequest(),
                where: "component == nil AND shoppingCarts.@count == 0",
                in: context
            )

            guard context.hasChanges else {
                defaults.set(true, forKey: Self.orphanCleanupKey)
                AppLog.persistence.info("Orphan cleanup found nothing to remove")
                return
            }

            do {
                try context.save()
                defaults.set(true, forKey: Self.orphanCleanupKey)
                AppLog.persistence.info("Orphan cleanup removed \(deleted) leftover objects")
            } catch {
                context.rollback()
                AppLog.persistence.error("Orphan cleanup failed, will retry on next launch: \(error)")
            }
        }
    }

    /// Deletes every object matching `predicateFormat` and returns how many were
    /// marked for deletion. Uses ordinary deletes instead of an
    /// `NSBatchDeleteRequest` so the model's cascade rules apply and the changes
    /// propagate through CloudKit.
    private static func deleteObjects<T: NSManagedObject>(
        _ request: NSFetchRequest<T>,
        where predicateFormat: String,
        in context: NSManagedObjectContext
    ) -> Int {
        request.predicate = NSPredicate(format: predicateFormat)
        request.returnsObjectsAsFaults = false

        guard let objects = try? context.fetch(request) else { return 0 }

        var deleted = 0
        for object in objects where !object.isDeleted {
            context.delete(object)
            deleted += 1
        }
        return deleted
    }
}
