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

    private let store: KitchenDishStore

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
            // Without a file the app still runs; the dishes just do not keep.
            let library = DishLibrary(store: InMemoryKitchenDishStore())
            library.lastError = error.localizedDescription
            return library
        }
    }

    func reload() {
        do {
            dishes = try store.dishes()
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
        } catch {
            lastError = error.localizedDescription
        }
    }
}
