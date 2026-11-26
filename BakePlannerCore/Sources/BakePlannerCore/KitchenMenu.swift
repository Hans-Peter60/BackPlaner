//
//  KitchenMenu.swift
//  BakePlannerCore
//
//  Several dishes as one plan: a menu of courses cooked against one clock
//  in one kitchen. The courses become one combined dish — every step and
//  ingredient keeps its course as a prefix ("Vorspeise – Salat"; the list
//  joins components with a middle dot, so the dash keeps them apart) — and the
//  gap between two courses is a step of its own with no hands and no
//  station: "Vorspeise servieren", as long as the guests eat. The next
//  course's final steps wait for it, so the scheduler plates the starter
//  that many minutes before the main and cooks the main while it is eaten.
//  The result is an ordinary dish: planned, cooked, shared and synced like
//  any other.
//

import Foundation

/// One course of a menu: the dish, how it is called in the plan ("Vorspeise"),
/// and how many minutes pass between serving it and plating the next.
public struct KitchenMenuCourse: Equatable, Sendable {
    public var dish: KitchenDish
    public var label: String
    /// Minutes between this course on the table and the next one plated; 0
    /// serves them together. Ignored on the last course.
    public var gapAfterMinutes: Int

    public init(dish: KitchenDish, label: String, gapAfterMinutes: Int = 0) {
        self.dish = dish
        self.label = label
        self.gapAfterMinutes = max(0, gapAfterMinutes)
    }
}

public enum KitchenMenu {

    /// The id of the serving step of course `index`.
    public static func servingStepID(course index: Int) -> String { "c\(index)-serve" }

    /// The courses as one dish. `serveTitle` words the serving step for a
    /// course label — the app passes its localized "%@ servieren".
    public static func combined(name: String, courses: [KitchenMenuCourse], id: String = UUID().uuidString,
                                createdAt: Date = Date(), serveTitle: (String) -> String) -> KitchenDish {
        var tasks = [KitchenTask]()
        var ingredients = [KitchenIngredient]()
        /// The steps of the previous course that the next course's final
        /// steps wait for: its serving step, or its own finals with no gap.
        var waitFor: [String] = []
        for (index, course) in courses.enumerated() {
            let prefix = "c\(index)-"
            let label = course.label.trimmingCharacters(in: .whitespaces)
            func component(_ name: String) -> String {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty || trimmed == label ? label : label + " – " + trimmed
            }
            let ids = Set(course.dish.tasks.map(\.id))
            let dependedOn = Set(course.dish.tasks.flatMap(\.after))
            let finals = course.dish.tasks.filter { !dependedOn.contains($0.id) }.map { prefix + $0.id }
            for task in course.dish.tasks {
                var after = task.after.filter(ids.contains).map { prefix + $0 }
                if finals.contains(prefix + task.id) { after += waitFor }
                tasks.append(KitchenTask(id: prefix + task.id, name: task.name, component: component(task.component),
                                         hands: task.handsMinutes, unattended: task.unattendedMinutes,
                                         station: task.station, after: after, maxWait: task.maxWait,
                                         window: task.unattendedWindow, ovenTemperature: task.ovenTemperature,
                                         ingredientIDs: task.ingredientIDs.map { prefix + $0 }))
            }
            for ingredient in course.dish.ingredients {
                ingredients.append(KitchenIngredient(id: prefix + ingredient.id, name: ingredient.name,
                                                     amount: ingredient.amount, unit: ingredient.unit,
                                                     component: component(ingredient.component), note: ingredient.note))
            }
            if index < courses.count - 1, course.gapAfterMinutes > 0 {
                let serve = servingStepID(course: index)
                tasks.append(KitchenTask(id: serve, name: serveTitle(label), component: label,
                                         hands: 0, unattended: course.gapAfterMinutes, after: finals))
                waitFor = [serve]
            } else {
                waitFor = finals
            }
        }
        return KitchenDish(id: id, name: name, source: .menu, servings: nil, createdAt: createdAt,
                           tasks: tasks, ingredients: ingredients).consistent()
    }
}
