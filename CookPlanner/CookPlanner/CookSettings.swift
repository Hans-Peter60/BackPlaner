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
    /// How the cook mode's clock runs, chosen before the start.
    static let clockModeKey = "settings.clockMode"
    /// Whether the cook mode reads each new step and each pot that is
    /// done aloud on its own.
    static let readAloudKey = "settings.readAloud"

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

    /// Why no plan comes out of the dish, in the cook's words; nil when
    /// one does. The list and the plan screen show this instead of nothing.
    static func failure(dish: KitchenDish, budget: Int, burners: Int, ovens: Int) -> LocalizedStringKey? {
        do {
            _ = try KitchenScheduler.schedule(dish.tasks, kitchen: Kitchen(burners: burners, ovens: ovens), budget: budget)
            return nil
        } catch KitchenSchedulingError.stationMissing(let station) {
            switch station {
            case .oven: return "Das Gericht braucht einen Ofen; in den Einstellungen steht die Küche auf 0 Öfen."
            case .burner: return "Das Gericht braucht eine Herdplatte; in den Einstellungen steht die Küche auf 0 Platten."
            }
        } catch KitchenSchedulingError.unknownDependency(let task, _) {
            let name = dish.tasks.first { $0.id == task }?.name ?? task
            return "„\(name)“ wartet auf einen Schritt, den es nicht mehr gibt. Den Schritt bearbeiten und sichern räumt das auf."
        } catch KitchenSchedulingError.cycle {
            return "Die Schritte warten im Kreis aufeinander. Die Reihenfolge der Schritte prüfen."
        } catch {
            return "Der Plan geht nicht auf: \(error.localizedDescription)"
        }
    }

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

/// "Challenge": the clock counts the time budget down, like on the show,
/// and on into the minus. "Training": a stopwatch from 0:00, to learn how
/// long the dish really takes. "Entspannt": no clock on screen at all —
/// the steps come in their order, the pots keep their timers, nothing
/// says overdue. All three keep the record of the steps; a relaxed run
/// teaches the plan nothing.
enum CookClockMode: String, CaseIterable {
    case challenge
    case training
    case relaxed

    var title: LocalizedStringKey {
        switch self {
        case .challenge: return "Challenge"
        case .training: return "Training"
        case .relaxed: return "Entspannt"
        }
    }

    var explanation: LocalizedStringKey {
        switch self {
        case .challenge: return "Die Uhr zählt das Zeitbudget rückwärts, wie in der Sendung."
        case .training: return "Die Uhr läuft ab 0:00 – so lernst Du, wie lange das Gericht wirklich dauert."
        case .relaxed: return "Keine Uhr, kein Überfällig: Die Schritte kommen der Reihe nach, nur Topf und Ofen behalten ihre Zeit."
        }
    }

    /// Whether the screen shows the clock and the minutes left on a step.
    var showsClock: Bool { self != .relaxed }
}
