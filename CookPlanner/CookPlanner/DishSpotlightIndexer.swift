//
//  DishSpotlightIndexer.swift
//  CookPlanner
//
//  Keeps the dishes in the app's Spotlight index as DishEntity items: all
//  of them once per launch, and again whenever the library changed — a
//  save, a delete, a dish from iCloud. Dishes that are gone leave the
//  index too; the ids indexed last time are kept in UserDefaults for that.
//  Changes come in bursts (a backup import saves every dish), so the pass
//  runs two seconds after the last one.
//

import AppIntents
import CoreSpotlight
import Foundation
import os

@MainActor
final class DishSpotlightIndexer {

    static let shared = DishSpotlightIndexer()

    /// A named index, as Apple asks for in production.
    static let indexName = "CookPlannerDishes"
    private static let indexedIDsKey = "spotlight.indexedDishIDs"
    private static let log = Logger(subsystem: "de.hpm64625.CookPlanner", category: "spotlight")

    private var pendingPass: Task<Void, Never>?

    private init() {}

    /// Indexes every dish shortly; called at launch and after every change.
    func schedulePass() {
        pendingPass?.cancel()
        pendingPass = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            do {
                try await self?.indexAll()
            } catch {
                Self.log.error("Spotlight: dishes could not be indexed: \(error.localizedDescription)")
            }
        }
    }

    /// Every dish into the index, dishes that are gone out of it.
    func indexAll() async throws {
        let entities = DishLookup.all().map(DishEntity.init)
        let index = CSSearchableIndex(name: Self.indexName)
        let current = Set(entities.map(\.id))
        let previous = Set(UserDefaults.standard.stringArray(forKey: Self.indexedIDsKey) ?? [])
        let gone = Array(previous.subtracting(current))
        if !gone.isEmpty {
            try await index.deleteAppEntities(identifiedBy: gone, ofType: DishEntity.self)
        }
        if !entities.isEmpty {
            try await index.indexAppEntities(entities)
        }
        UserDefaults.standard.set(Array(current), forKey: Self.indexedIDsKey)
        Self.log.info("Spotlight: \(entities.count) dishes indexed, \(gone.count) removed")
    }
}
