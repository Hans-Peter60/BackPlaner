import BakePlannerCore
import Foundation

/// The plan of a dish for the current settings, with the words the screens
/// show for its verdict — the iPhone's DishPlan (CookSettings.swift there),
/// with texts as Strings, since Skip looks up localized keys in views only.
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

    /// Why no plan comes out of the dish; nil when one does.
    static func failure(dish: KitchenDish, budget: Int, burners: Int, ovens: Int) -> String? {
        do {
            _ = try KitchenScheduler.schedule(dish.tasks, kitchen: Kitchen(burners: burners, ovens: ovens), budget: budget)
            return nil
        } catch KitchenSchedulingError.stationMissing(let station) {
            switch station {
            case .oven: return String(localized: "Das Gericht braucht einen Ofen; in den Einstellungen steht die Küche auf 0 Öfen.", bundle: .module)
            case .burner: return String(localized: "Das Gericht braucht eine Herdplatte; in den Einstellungen steht die Küche auf 0 Platten.", bundle: .module)
            }
        } catch KitchenSchedulingError.cycle {
            return String(localized: "Die Schritte warten im Kreis aufeinander. Die Reihenfolge der Schritte prüfen.", bundle: .module)
        } catch {
            return String(localized: "Der Plan geht nicht auf.", bundle: .module)
        }
    }

    /// "Passt in 35 Minuten" or "Fehlen 9 Minuten".
    var verdict: String {
        if schedule.fits {
            return String(localized: "Passt in \(schedule.budget ?? schedule.makespan) Minuten", bundle: .module)
        }
        return String(localized: "Fehlen \(schedule.shortfall) Minuten", bundle: .module)
    }

    /// Why the dish does not fit, or how much room is left.
    var reason: String {
        switch schedule.limit {
        case .criticalPath:
            return String(localized: "Die längste Kette dauert \(schedule.criticalPathMinutes) Minuten. Parallel arbeiten hilft nicht, nur kürzere Schritte.", bundle: .module)
        case .hands:
            return String(localized: "Die Handarbeit allein dauert \(schedule.handsMinutes) Minuten. Eine Person reicht nicht: Schritte streichen oder vereinfachen.", bundle: .module)
        case .packing:
            return String(localized: "Kette (\(schedule.criticalPathMinutes) Minuten) und Hände (\(schedule.handsMinutes) Minuten) passen einzeln, kollidieren aber an Händen oder Geräten.", bundle: .module)
        case nil:
            return String(localized: "\(schedule.slack) Min. Luft, \(schedule.idleHandsMinutes) Min. ohne Handarbeit.", bundle: .module)
        }
    }
}
