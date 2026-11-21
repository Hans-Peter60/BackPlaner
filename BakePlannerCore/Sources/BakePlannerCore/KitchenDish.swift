//
//  KitchenDish.swift
//  BakePlannerCore
//
//  A dish as the CookPlanner app keeps it: its work steps (KitchenTask),
//  where it came from and for how many. The dependency defaults spare the
//  cook drawing arrows: steps of one component follow one another, and the
//  last step waits for every component.
//

import Foundation

/// Where a dish came from.
public enum KitchenDishSource: String, Equatable, Hashable, Sendable, CaseIterable {
    /// One of the app's examples.
    case sample
    /// Typed in by the cook.
    case manual
    /// Read by the cloud AI from pasted text.
    case text
    /// Read by the cloud AI from photos.
    case photo
    /// Read from a web page.
    case web
}

/// A dish as a set of work steps.
public struct KitchenDish: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var source: KitchenDishSource
    /// How many the recipe serves, when it says.
    public var servings: Int?
    /// When the dish was created, nil for the examples.
    public var createdAt: Date?
    public var tasks: [KitchenTask]
    /// What goes in, for the shopping list and the steps that name them.
    public var ingredients: [KitchenIngredient]

    public init(id: String = UUID().uuidString, name: String, source: KitchenDishSource = .manual,
                servings: Int? = nil, createdAt: Date? = nil, tasks: [KitchenTask],
                ingredients: [KitchenIngredient] = []) {
        self.id = id
        self.name = name
        self.source = source
        self.servings = servings
        self.createdAt = createdAt
        self.tasks = tasks
        self.ingredients = ingredients
    }

    /// The parts of the dish, in the order their steps first appear.
    public var components: [String] {
        var seen = [String]()
        for task in tasks where !task.component.isEmpty && !seen.contains(task.component) {
            seen.append(task.component)
        }
        return seen
    }

    /// A copy under a new identity, as a template taken from an example:
    /// the cook's own from now on.
    public func duplicate(named name: String? = nil, now: Date = Date()) -> KitchenDish {
        KitchenDish(id: UUID().uuidString, name: name ?? self.name, source: .manual, servings: servings,
                    createdAt: now, tasks: tasks, ingredients: ingredients)
    }
}

public enum KitchenDishDefaults {

    /// The steps with their dependencies filled in where none are given:
    /// a step follows the previous step of its component, and the last
    /// step of the dish — the plating — waits for the last step of every
    /// other component. Steps that name their own predecessors keep them.
    /// A step without a component follows the previous step without one.
    public static func withDependencies(_ tasks: [KitchenTask]) -> [KitchenTask] {
        var previousInComponent = [String: String]()
        var result = [KitchenTask]()
        for (index, task) in tasks.enumerated() {
            var after = task.after
            let isLast = index == tasks.count - 1
            if after.isEmpty {
                if isLast && tasks.count > 1 {
                    // Every component's last step, components in order of appearance.
                    var componentsInOrder = [String]()
                    var lastOf = [String: String]()
                    for other in tasks.dropLast() {
                        if lastOf[other.component] == nil { componentsInOrder.append(other.component) }
                        lastOf[other.component] = other.id
                    }
                    after = componentsInOrder.compactMap { lastOf[$0] }
                } else if let previous = previousInComponent[task.component] {
                    after = [previous]
                }
            }
            result.append(KitchenTask(id: task.id, name: task.name, component: task.component,
                                      hands: task.handsMinutes, unattended: task.unattendedMinutes,
                                      station: task.station, after: after, maxWait: task.maxWait,
                                      window: task.unattendedWindow, ovenTemperature: task.ovenTemperature,
                                      ingredientIDs: task.ingredientIDs))
            previousInComponent[task.component] = task.id
        }
        return result
    }
}
