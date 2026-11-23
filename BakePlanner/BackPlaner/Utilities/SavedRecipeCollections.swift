//
//  SavedRecipeCollections.swift
//  BackPlaner
//
//  The collections a person saves from the recipe list's facets: a name and
//  the filter behind it, kept in UserDefaults as JSON. They sit in the chip
//  row after the preset collections (RecipeCollection).
//

import BakePlannerCore
import Foundation
import Observation

/// The saved collections, in the order they were made; every change is
/// written straight back to the defaults.
@Observable
final class SavedRecipeCollectionStore {

    static let defaultsKey = "savedRecipeCollections"

    private(set) var collections: [SavedRecipeCollection]
    private let defaults: UserDefaults
    private let key: String

    private var remoteObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, key: String = SavedRecipeCollectionStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
        collections = Self.read(from: defaults, key: key)
        // Another device saved, renamed or removed a collection: read again.
        remoteObserver = NotificationCenter.default.addObserver(forName: SettingsSync.didApplyRemoteChanges, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    deinit {
        if let remoteObserver { NotificationCenter.default.removeObserver(remoteObserver) }
    }

    func reload() {
        collections = Self.read(from: defaults, key: key)
    }

    private static func read(from defaults: UserDefaults, key: String) -> [SavedRecipeCollection] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([SavedRecipeCollection].self, from: data) else { return [] }
        return stored
    }

    /// The name as it is kept: trimmed; empty means "no name", nothing is saved.
    static func cleanName(_ name: String) -> String? {
        SavedRecipeCollection.cleanName(name)
    }

    /// Saves the filter under the name; nothing happens for an empty name or
    /// an inactive filter. Returns what was saved.
    @discardableResult
    func add(name: String, filter: RecipeFacetFilter) -> SavedRecipeCollection? {
        guard let cleaned = Self.cleanName(name), filter.isActive else { return nil }
        let collection = SavedRecipeCollection(id: UUID(), name: cleaned, filter: filter)
        collections.append(collection)
        persist()
        return collection
    }

    /// Gives the collection a new name; an empty name is ignored.
    func rename(_ id: SavedRecipeCollection.ID, to name: String) {
        guard let cleaned = Self.cleanName(name),
              let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].name = cleaned
        persist()
    }

    func remove(_ id: SavedRecipeCollection.ID) {
        collections.removeAll { $0.id == id }
        persist()
    }

    /// The saved collection whose facets are exactly these, if any — that
    /// chip is shown selected, and "Als Sammlung sichern" is not offered.
    func collection(matching filter: RecipeFacetFilter) -> SavedRecipeCollection? {
        collections.first { $0.filter == filter }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(collections) {
            defaults.set(data, forKey: key)
        }
    }
}
