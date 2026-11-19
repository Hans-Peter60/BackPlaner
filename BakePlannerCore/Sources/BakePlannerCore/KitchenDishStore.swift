//
//  KitchenDishStore.swift
//  BakePlannerCore
//
//  Where the CookPlanner app keeps the cook's own dishes. The protocol
//  lives in the core so the screens and the contract do not depend on a
//  database; CookPlannerStorage keeps them in SQLite, the in-memory store
//  serves tests and previews.
//

import Foundation

public protocol KitchenDishStore {
    /// Every dish, by name.
    func dishes() throws -> [KitchenDish]
    /// The dish with this id, nil for an unknown one.
    func dish(id: String) throws -> KitchenDish?
    /// Keeps the dish: a new one is added, one with a known id replaced
    /// whole, steps included.
    func save(_ dish: KitchenDish) throws
    /// Removes the dish. Nothing happens for an unknown id.
    func delete(id: String) throws
}

public enum KitchenDishStoreError: LocalizedError, Equatable {
    /// A dish without a name or without an id cannot be kept.
    case incomplete
}
