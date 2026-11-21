//
//  KitchenDishTransfer.swift
//  BakePlannerCore
//
//  Dishes leaving and entering CookPlanner as a file: a backup of all own
//  dishes, or one dish sent to someone. The file is a KitchenDishFile; this
//  is the naming and the merge. Reading a file never replaces anything: a
//  dish the app already has (same id) stays as it is, so restoring an old
//  backup cannot undo later edits, and the examples are never doubled.
//

import Foundation

public enum KitchenDishTransfer {

    /// The file name extension, declared as an exported type by the app.
    public static let fileExtension = "cookplanner"

    public struct MergeResult: Equatable, Sendable {
        /// The dishes to keep, as own dishes.
        public var added: [KitchenDish]
        /// Dishes the app already had, or examples.
        public var alreadyThere: Int
    }

    /// What of `incoming` is new next to `existing`. An example of this
    /// app's set counts as there; one the app does not know (an older
    /// example, or another version) comes in as an own dish.
    public static func merge(_ incoming: [KitchenDish], into existing: [KitchenDish],
                             examples: [KitchenDish] = KitchenSampleDishes.all) -> MergeResult {
        var known = Set(existing.map(\.id)).union(examples.map(\.id))
        var added: [KitchenDish] = []
        var alreadyThere = 0
        for dish in incoming {
            guard !known.contains(dish.id) else {
                alreadyThere += 1
                continue
            }
            known.insert(dish.id)
            var own = dish
            if own.source == .sample { own.source = .manual }
            added.append(own)
        }
        return MergeResult(added: added, alreadyThere: alreadyThere)
    }

    /// "Beef Wellington.cookplanner" for one dish, otherwise
    /// "CookPlanner 2026-11-21.cookplanner".
    public static func fileName(for dishes: [KitchenDish], date: Date = .now) -> String {
        if dishes.count == 1, let name = dishes.first?.name {
            let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return String(cleaned.prefix(80)) + "." + fileExtension }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "CookPlanner \(day).\(fileExtension)"
    }
}
