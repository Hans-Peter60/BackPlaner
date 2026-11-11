//
//  CoreDataPantryStore.swift
//  BackPlaner
//
//  The pantry kept in Core Data (and iCloud) — the iOS side of PantryStore.
//  Keys are object IDs, like those of the other Core Data stores.
//

import BakePlannerCore
import CoreData
import Foundation

struct CoreDataPantryStore: PantryStore {

    let context: NSManagedObjectContext

    func items() throws -> [StoredPantryItem] {
        let request = PantryItem.fetchRequest()
        return try context.fetch(request)
            .map(Self.stored)
            .sorted { Self.ordered($0, $1) }
    }

    func add(name: String, amount: Double, unit: PantryUnit, bestBefore: Date?, note: String) throws -> StoredPantryItem {
        let content = StoredPantryItem(id: "", name: name, amount: amount, unit: unit, bestBefore: bestBefore, note: note).normalized
        guard !content.name.isEmpty else { throw PantryStoreError.emptyName }
        let item = PantryItem(context: context)
        item.id = UUID()
        item.updatedAt = Date()
        Self.apply(content, to: item)
        try save()
        return Self.stored(item)
    }

    func update(_ updated: StoredPantryItem) throws {
        guard let item: PantryItem = context.existingObject(storeKey: updated.id) else {
            throw PantryStoreError.unknownItem(updated.id)
        }
        let content = updated.normalized
        guard !content.name.isEmpty else { throw PantryStoreError.emptyName }
        Self.apply(content, to: item)
        item.updatedAt = Date()
        try save()
    }

    func delete(id: String) throws {
        guard let item: PantryItem = context.existingObject(storeKey: id) else { return }
        context.delete(item)
        try save()
    }

    // MARK: Helpers

    /// The pantry's order: by name, equal names by key.
    static func ordered(_ a: StoredPantryItem, _ b: StoredPantryItem) -> Bool {
        let names = a.name.localizedStandardCompare(b.name)
        return names != .orderedSame ? names == .orderedAscending : a.id < b.id
    }

    static func stored(_ item: PantryItem) -> StoredPantryItem {
        StoredPantryItem(id: item.storeKey,
                         name: item.name ?? "",
                         amount: item.amount,
                         unit: PantryUnit(stored: item.unit),
                         bestBefore: item.bestBefore,
                         note: item.note ?? "",
                         updatedAt: item.updatedAt ?? .distantPast)
    }

    private static func apply(_ content: StoredPantryItem, to item: PantryItem) {
        item.name = content.name
        item.amount = content.amount
        item.unit = content.unit.rawValue
        item.bestBefore = content.bestBefore
        item.note = content.note.isEmpty ? nil : content.note
    }

    private func save() throws {
        guard context.hasChanges else { return }
        try context.save()
        // The reminders follow the pantry; worked out on the main actor,
        // where the settings and the entitlements live.
        let items = try items()
        Task { @MainActor in PantryReminders.reconcile(items: items) }
    }
}
