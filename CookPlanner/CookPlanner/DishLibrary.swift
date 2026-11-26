//
//  DishLibrary.swift
//  CookPlanner
//
//  The cook's own dishes, loaded from the store once and kept for the
//  screens; every change goes to the store first and to the list after.
//  The examples stay apart in KitchenSampleDishes.
//

import BakePlannerCore
import CookPlannerStorage
import Foundation
import Observation

@Observable
@MainActor
final class DishLibrary {

    private(set) var dishes: [KitchenDish] = []
    /// The last failure of the store, for a sheet or a footnote.
    var lastError: String?
    /// Why the dishes are not being kept on disk, shown as a banner for as
    /// long as it is so; nil when the database file is in use.
    private(set) var storageWarning: String?

    private let store: KitchenDishStore
    /// The library the app runs on, for the App Intents and the Spotlight
    /// index, which have no view to get it from.
    static weak var current: DishLibrary?

    init(store: KitchenDishStore) {
        self.store = store
        reload()
    }

    /// The library on the app's database file in Application Support.
    static func onDisk() -> DishLibrary {
        do {
            let folder = URL.applicationSupportDirectory.appendingPathComponent("CookPlanner", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let store = try SQLiteKitchenDishStore(path: folder.appendingPathComponent("dishes.sqlite").path)
            return DishLibrary(store: store)
        } catch {
            // Without a file the app still runs; the dishes just do not
            // keep. The list says so for as long as that is the case,
            // instead of one alert that is gone by the next save.
            let library = DishLibrary(store: InMemoryKitchenDishStore())
            if case CookPlannerDatabaseError.newerSchema = error {
                library.storageWarning = String(localized: "Die Gerichte stammen von einer neueren Version von CookPlanner. Bis die App aktualisiert ist, werden Änderungen nicht gesichert.")
            } else {
                library.storageWarning = String(localized: "Die Datenbank der Gerichte lässt sich nicht öffnen (\(error.localizedDescription)). Änderungen gehen beim Beenden der App verloren.")
            }
            return library
        }
    }

    func reload() {
        do {
            dishes = try store.dishes()
            if Self.current === self { DishSpotlightIndexer.shared.schedulePass() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func dish(id: String) -> KitchenDish? {
        dishes.first { $0.id == id }
    }

    /// Keeps the dish, new or changed, and returns whether it was kept.
    @discardableResult
    func save(_ dish: KitchenDish) -> Bool {
        do {
            try store.save(dish)
            reload()
            CloudSync.shared.dishChanged(dish.id)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func delete(id: String) {
        do {
            try store.delete(id: id)
            reload()
            CloudSync.shared.dishDeleted(id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// A dish another device changed, kept without being sent back.
    func applyRemote(_ dish: KitchenDish) {
        guard self.dish(id: dish.id) != dish else { return }
        do {
            try store.save(dish)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Dishes another device changed, in one go: one reload for all.
    func applyRemote(_ incoming: [KitchenDish]) {
        var changed = false
        for dish in incoming where self.dish(id: dish.id) != dish {
            do {
                try store.save(dish)
                changed = true
            } catch {
                lastError = error.localizedDescription
            }
        }
        if changed { reload() }
    }

    /// A dish another device deleted.
    func removeRemote(id: String) {
        guard dish(id: id) != nil else { return }
        try? store.delete(id: id)
        reload()
    }
}
