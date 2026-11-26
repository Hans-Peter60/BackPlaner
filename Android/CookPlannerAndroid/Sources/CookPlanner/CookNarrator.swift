import BakePlannerCore
import Foundation

/// The sentences the cook mode says (the iPhone's CookNarrator), in the
/// app's language: a step for the ear, a pot that is done, the end.
struct CookNarrator {
    let dish: KitchenDish
    let showsClock: Bool
    let minute: Int

    /// Component, name, ingredients, oven, and how long.
    func stepSentence(_ placement: KitchenPlacement) -> String {
        let task = placement.task
        var parts = [String]()
        parts.append(task.component.isEmpty ? task.name + "." : task.component + ": " + task.name + ".")
        let ingredients = dish.ingredients(for: task)
        if !ingredients.isEmpty {
            parts.append(KitchenSpokenText.lines(for: ingredients, locale: AppSettings.locale) + ".")
        }
        if let temperature = task.ovenTemperature {
            parts.append(String(localized: "Ofen \(temperature) Grad.", bundle: .module))
        }
        if showsClock && task.handsMinutes > 0 {
            let left = placement.start + task.handsMinutes - minute
            parts.append(left > 0 ? String(localized: "\(left) Minuten.", bundle: .module)
                                  : String(localized: "Überfällig.", bundle: .module))
        }
        if task.unattendedMinutes > 0 {
            parts.append(String(localized: "Dann \(task.unattendedMinutes) Minuten von allein.", bundle: .module))
        }
        return parts.joined(separator: " ")
    }

    /// "Wirsing cremig garen: die Zeit ist um."
    func potDone(_ name: String) -> String {
        String(localized: "\(name /*%@*/): die Zeit ist um.", bundle: .module)
    }

    var allDone: String { String(localized: "Fertig, anrichten!", bundle: .module) }
}
