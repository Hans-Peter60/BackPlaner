//
//  CookSettings.swift
//  CookPlanner
//
//  The kitchen and the budget the plans are made for, kept in the defaults.
//

import BakePlannerCore
import SwiftUI

enum CookSettings {
    static let budgetKey = "settings.budgetMinutes"
    static let burnersKey = "settings.burners"
    static let ovensKey = "settings.ovens"

    static let defaultBudget = KitchenSampleDishes.budget
    static let defaultBurners = 4
    static let defaultOvens = 1
    /// Whether pots and ovens ring an alarm when their time is up.
    static let alarmsKey = "settings.alarms"
    static let defaultAlarms = true

    /// The portion factor chosen for a dish, 1 when none was chosen.
    static func portionFactor(for dishID: String) -> Double {
        let factor = UserDefaults.standard.double(forKey: "portions." + dishID)
        return factor > 0 ? factor : 1
    }

    static func setPortionFactor(_ factor: Double, for dishID: String) {
        if factor == 1 {
            UserDefaults.standard.removeObject(forKey: "portions." + dishID)
        } else {
            UserDefaults.standard.set(factor, forKey: "portions." + dishID)
        }
    }
}

/// The plan of a dish for the current settings, with the words the screens
/// show for its verdict.
struct DishPlan {
    let dish: KitchenDish
    let schedule: KitchenSchedule

    init?(dish: KitchenDish, budget: Int, burners: Int, ovens: Int) {
        guard let schedule = try? KitchenScheduler.schedule(dish.tasks, kitchen: Kitchen(burners: burners, ovens: ovens),
                                                            budget: budget) else { return nil }
        self.dish = dish
        self.schedule = schedule
    }

    var fits: Bool { schedule.fits }

    /// "Passt in 35 Minuten" or "Fehlen 9 Minuten".
    var verdict: LocalizedStringKey {
        if schedule.fits {
            return "Passt in \(schedule.budget ?? schedule.makespan) Minuten"
        }
        return "Fehlen \(schedule.shortfall) Minuten"
    }

    /// Why the dish does not fit, or how much room is left.
    var reason: LocalizedStringKey {
        switch schedule.limit {
        case .criticalPath:
            return "Die längste Kette dauert \(schedule.criticalPathMinutes) Minuten. Parallel arbeiten hilft nicht, nur kürzere Schritte."
        case .hands:
            return "Die Handarbeit allein dauert \(schedule.handsMinutes) Minuten. Eine Person reicht nicht: Schritte streichen oder vereinfachen."
        case .packing:
            return "Kette (\(schedule.criticalPathMinutes) Minuten) und Hände (\(schedule.handsMinutes) Minuten) passen einzeln, kollidieren aber an Händen oder Geräten."
        case nil:
            return "\(schedule.slack) Min. Luft, \(schedule.idleHandsMinutes) Min. ohne Handarbeit."
        }
    }
}

extension KitchenTask {
    /// The symbol for where the step happens.
    var stationSymbol: String? {
        switch station {
        case .burner: return "flame"
        case .oven: return "oven"
        case nil: return nil
        }
    }
}

extension KitchenTask {
    /// The same step naming other ingredients.
    func withIngredientIDs(_ ids: [String]) -> KitchenTask {
        KitchenTask(id: id, name: name, component: component, hands: handsMinutes, unattended: unattendedMinutes,
                    station: station, after: after, maxWait: maxWait, window: unattendedWindow,
                    ovenTemperature: ovenTemperature, ingredientIDs: ids)
    }
}
