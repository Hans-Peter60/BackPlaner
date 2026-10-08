//
//  Persistence.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 08.02.24.
//

import CoreData
import CloudKit

struct PersistenceController {
    /// The app's store. A UI test run gets a fresh in-memory one instead (see
    /// UITestSupport), so it neither depends on nor touches the real recipes.
    static let shared = PersistenceController(inMemory: UITestSupport.isActive)

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        return result
    }()

    let container: NSPersistentCloudKitContainer

    /// Why the store on disk could not be opened, if it could not. The app
    /// then runs on an empty in-memory store and ContentView explains it,
    /// instead of stopping at launch: a full device or a failed migration
    /// used to end in a crash with no word to the user.
    let loadError: NSError?

    private static let cloudKitContainerIdentifier = "iCloud.de.hpm64625.BackPlaner"

    init(inMemory: Bool = false) {
        let container = NSPersistentCloudKitContainer(name: "BackPlaner")

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

        // Stores are added synchronously (the default), so the error is known
        // once this returns. Typical causes: the device is out of space, the
        // store is locked by data protection, or it could not be migrated.
        var failure: NSError?
        container.loadPersistentStores { _, error in
            if let error = error as NSError? { failure = error }
        }

        if let failure {
            AppLog.persistence.error("Store could not be loaded, running in memory: \(failure), \(failure.userInfo)")
            // The file on disk is left untouched, so the recipes are there
            // again once the cause is gone and the app is restarted.
            let fallback = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            fallback.cloudKitContainerOptions = nil
            container.persistentStoreDescriptions = [fallback]
            container.loadPersistentStores { _, error in
                if let error {
                    AppLog.persistence.error("In-memory fallback store failed too: \(error)")
                }
            }
        }

        self.container = container
        self.loadError = failure

        #if DEBUG
        initializeCloudKitSchemaIfRequested()
        #endif
    }

    #if DEBUG
    /// Pushes the whole managed object model into the CloudKit **Development**
    /// schema when the app is launched with `-initializeCloudKitSchema`.
    ///
    /// CloudKit only learns a field once a record carrying it has been
    /// written, so an attribute no user has filled yet does not exist in
    /// Development and cannot be deployed to Production — new bake-history
    /// fields would then silently never sync for store users. This creates
    /// (and removes again) one record of every entity with every attribute
    /// set, which is what the schema deployment in the CloudKit Console
    /// needs to see. Debug builds only: they alone talk to Development.
    private func initializeCloudKitSchemaIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-initializeCloudKitSchema"),
              loadError == nil else { return }
        do {
            try container.initializeCloudKitSchema(options: [.printSchema])
            AppLog.persistence.info("CloudKit development schema initialized from the managed object model")
        } catch {
            AppLog.persistence.error("CloudKit schema initialization failed: \(error)")
        }
    }
    #endif
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
        // On the empty fallback store the pass would succeed without touching
        // the real one, and the flag would keep it from ever running there.
        guard loadError == nil else { return }

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
