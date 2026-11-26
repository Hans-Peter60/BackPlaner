//
//  DishCollections.swift
//  CookPlanner
//
//  The titles and symbols of the dish list's ready-made collections and
//  facets, and the collections the cook saves, kept in the defaults as
//  JSON. The filter itself is KitchenDishFilter in the package.
//

import BakePlannerCore
import Foundation
import Observation
import SwiftUI

extension KitchenDishCollection {
    var title: LocalizedStringKey {
        switch self {
        case .fits: "Passt ins Budget"
        case .quick: "Schnell"
        case .noOven: "Ohne Ofen"
        case .favourites: "Lieblinge"
        case .never: "Noch nie gekocht"
        case .longAgo: "Lange nicht gekocht"
        }
    }

    var systemImage: String {
        switch self {
        case .fits: "checkmark.circle"
        case .quick: "hare"
        case .noOven: "flame"
        case .favourites: "heart"
        case .never: "sparkles"
        case .longAgo: "clock.arrow.circlepath"
        }
    }
}

/// The saved collections in the order they were made; every change is
/// written straight back.
@Observable @MainActor
final class SavedDishCollectionStore {

    static let defaultsKey = "savedDishCollections"

    private(set) var collections: [SavedKitchenDishCollection]
    @ObservationIgnored private var remoteObserver: NSObjectProtocol?

    init() {
        collections = Self.stored()
        // Another device changed the collections: they arrive through the
        // settings mirror in the defaults and are read again here.
        remoteObserver = NotificationCenter.default.addObserver(
            forName: SettingsSync.didApplyRemoteChanges, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.collections = Self.stored() }
            }
    }

    deinit {
        if let remoteObserver { NotificationCenter.default.removeObserver(remoteObserver) }
    }

    private static func stored() -> [SavedKitchenDishCollection] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode([SavedKitchenDishCollection].self, from: data) else { return [] }
        return stored
    }

    /// Saves the filter under the name; nothing for an empty name or filter.
    func add(name: String, filter: KitchenDishFilter) {
        guard let cleaned = SavedKitchenDishCollection.cleanName(name), filter.isActive else { return }
        collections.append(SavedKitchenDishCollection(name: cleaned, filter: filter))
        persist()
    }

    func rename(_ id: SavedKitchenDishCollection.ID, to name: String) {
        guard let cleaned = SavedKitchenDishCollection.cleanName(name),
              let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].name = cleaned
        persist()
    }

    func remove(_ id: SavedKitchenDishCollection.ID) {
        collections.removeAll { $0.id == id }
        persist()
    }

    func collection(matching filter: KitchenDishFilter) -> SavedKitchenDishCollection? {
        collections.first { $0.filter == filter }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(collections) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
