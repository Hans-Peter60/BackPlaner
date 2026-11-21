//
//  KitchenDishFile.swift
//  BakePlannerCore
//
//  The file format for dishes: what the CookPlanner store keeps a dish as
//  and what a backup or a shared dish is. Plain records with explicit
//  keys, apart from the in-memory types, so the format can stay while the
//  types move. Version 1. Never change it without raising the version;
//  a file of a later version than the app knows is refused rather than
//  half read.
//

import Foundation

public struct KitchenDishFile: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var formatVersion: Int
    public var dishes: [KitchenDishRecord]

    public init(dishes: [KitchenDish]) {
        formatVersion = Self.currentVersion
        self.dishes = dishes.map(KitchenDishRecord.init(dish:))
    }

    /// The file read; a later version than this app knows is refused.
    public static func decode(_ data: Data) throws -> KitchenDishFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(KitchenDishFile.self, from: data)
        guard file.formatVersion <= currentVersion else {
            throw KitchenDishFileError.unsupportedVersion(file.formatVersion)
        }
        return file
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// The dishes as the app uses them.
    public var kitchenDishes: [KitchenDish] { dishes.map(\.dish) }
}

public enum KitchenDishFileError: Error, Equatable {
    case unsupportedVersion(Int)
}

public struct KitchenDishRecord: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var source: String
    public var servings: Int?
    public var createdAt: Date?
    public var steps: [KitchenStepRecord]
    /// Since format 2; a file of format 1 has none.
    public var ingredients: [KitchenIngredientRecord]?

    public init(dish: KitchenDish) {
        id = dish.id
        name = dish.name
        source = dish.source.rawValue
        servings = dish.servings
        createdAt = dish.createdAt
        steps = dish.tasks.map(KitchenStepRecord.init(task:))
        ingredients = dish.ingredients.map(KitchenIngredientRecord.init(ingredient:))
    }

    /// The dish; an unknown source reads as typed in by hand.
    public var dish: KitchenDish {
        KitchenDish(id: id, name: name, source: KitchenDishSource(rawValue: source) ?? .manual,
                    servings: servings.map { max(0, $0) }, createdAt: createdAt, tasks: steps.map(\.task),
                    ingredients: (ingredients ?? []).map(\.ingredient))
    }
}

public struct KitchenIngredientRecord: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var amount: Double?
    public var unit: String
    public var component: String
    public var note: String?

    public init(ingredient: KitchenIngredient) {
        id = ingredient.id
        name = ingredient.name
        amount = ingredient.amount
        unit = ingredient.unit
        component = ingredient.component
        note = ingredient.note.isEmpty ? nil : ingredient.note
    }

    public var ingredient: KitchenIngredient {
        KitchenIngredient(id: id, name: name, amount: amount, unit: unit, component: component, note: note ?? "")
    }
}

public struct KitchenStepRecord: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var component: String
    public var handsMinutes: Int
    public var unattendedMinutes: Int
    /// "burner", "oven" or nil.
    public var station: String?
    public var after: [String]
    public var maxWait: Int?
    public var windowMinimum: Int?
    public var windowMaximum: Int?
    public var ovenTemperature: Int?
    /// Since format 2.
    public var ingredientIDs: [String]?

    public init(task: KitchenTask) {
        ingredientIDs = task.ingredientIDs.isEmpty ? nil : task.ingredientIDs
        id = task.id
        name = task.name
        component = task.component
        handsMinutes = task.handsMinutes
        unattendedMinutes = task.unattendedMinutes
        station = task.station?.rawValue
        after = task.after
        maxWait = task.maxWait
        windowMinimum = task.unattendedWindow?.lowerBound
        windowMaximum = task.unattendedWindow?.upperBound
        ovenTemperature = task.ovenTemperature
    }

    /// The step; numbers are held to plausible ranges, an unknown station
    /// is none, a window needs both ends.
    public var task: KitchenTask {
        var window: ClosedRange<Int>?
        if let low = windowMinimum, let high = windowMaximum, low <= high {
            window = Plausible.minutes(low)...Plausible.minutes(high)
        }
        return KitchenTask(id: id, name: name, component: component,
                           hands: Plausible.minutes(handsMinutes), unattended: Plausible.minutes(unattendedMinutes),
                           station: station.flatMap(KitchenStation.init(rawValue:)), after: after,
                           maxWait: maxWait.map(Plausible.minutes), window: window,
                           ovenTemperature: ovenTemperature.flatMap { Plausible.temperature(Double($0)).map(Int.init) },
                           ingredientIDs: ingredientIDs ?? [])
    }
}
