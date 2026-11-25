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

    /// The dish with only references that lead somewhere: a second step
    /// with an id already taken is dropped, a step no longer waits for
    /// itself or for a step that is not there, and names an ingredient
    /// only if the dish has it. Edited and imported dishes pass through
    /// here, so a deleted step cannot leave a plan that never works out
    /// and a dish that never shows in the list.
    public func consistent() -> KitchenDish {
        var ids = Set<String>()
        var unique = [KitchenTask]()
        for task in tasks where !ids.contains(task.id) {
            ids.insert(task.id)
            unique.append(task)
        }
        let ingredientIDs = Set(ingredients.map(\.id))
        var dish = self
        dish.tasks = unique.map { task in
            let after = task.after.filter { $0 != task.id && ids.contains($0) }
            let named = task.ingredientIDs.filter(ingredientIDs.contains)
            guard after != task.after || named != task.ingredientIDs else { return task }
            return task.withAfter(after).withIngredientIDs(named)
        }
        return dish
    }

    /// The dish without the steps `ids`; what waited for them waits for
    /// what they waited for, so the chain of a component does not break.
    public func removingTasks(ids removed: Set<String>) -> KitchenDish {
        let predecessors = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.after) })
        var dish = self
        dish.tasks = tasks.filter { !removed.contains($0.id) }.map { task in
            var after = [String]()
            var queue = task.after
            while !queue.isEmpty {
                let id = queue.removeFirst()
                if removed.contains(id) {
                    queue.append(contentsOf: predecessors[id] ?? [])
                } else if !after.contains(id) {
                    after.append(id)
                }
            }
            return after == task.after ? task : task.withAfter(after)
        }
        return dish.consistent()
    }
}

extension KitchenTask {

    /// The same step waiting for `after` instead.
    public func withAfter(_ after: [String]) -> KitchenTask {
        KitchenTask(id: id, name: name, component: component, hands: handsMinutes, unattended: unattendedMinutes,
                    station: station, after: after, maxWait: maxWait, window: unattendedWindow,
                    ovenTemperature: ovenTemperature, ingredientIDs: ingredientIDs)
    }

    /// The same step with `ids` as the ingredients it takes in hand.
    public func withIngredientIDs(_ ids: [String]) -> KitchenTask {
        KitchenTask(id: id, name: name, component: component, hands: handsMinutes, unattended: unattendedMinutes,
                    station: station, after: after, maxWait: maxWait, window: unattendedWindow,
                    ovenTemperature: ovenTemperature, ingredientIDs: ids)
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
