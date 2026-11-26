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

    /// What comes next: the next step in the hands, or what the hands wait for.
    func followUp(handsNow: [KitchenPlacement], schedule: KitchenSchedule, finished: [String: Int]) -> String {
        if let next = handsNow.first {
            return String(localized: "Jetzt:", bundle: .module) + " " + stepSentence(next)
        }
        let upcoming = schedule.placements.filter { $0.start > minute && $0.task.handsMinutes > 0 }
            .sorted { ($0.start, $0.task.id) < ($1.start, $1.task.id) }
        if let next = upcoming.first {
            let wait = next.start - minute
            let name = next.task.name
            return showsClock
                ? String(localized: "Gleich, in \(wait) Minuten: \(name /*%@*/).", bundle: .module)
                : String(localized: "Gleich: \(name /*%@*/).", bundle: .module)
        }
        if let pot = running(schedule: schedule, finished: finished).min(by: { $0.end < $1.end }) {
            let name = pot.task.name
            let left = pot.end - minute
            return String(localized: "\(name /*%@*/) braucht noch \(left) Minuten.", bundle: .module)
        }
        return String(localized: "Das war der letzte Schritt. Fertig, anrichten!", bundle: .module)
    }

    /// The time left on the step in the hands, on every pot, and on the plan.
    func timing(handsNow: [KitchenPlacement], schedule: KitchenSchedule, finished: [String: Int]) -> String {
        var parts = [String]()
        if let current = handsNow.first, showsClock {
            let left = current.start + current.task.handsMinutes - minute
            let name = current.task.name
            parts.append(left > 0 ? String(localized: "Noch \(left) Minuten für \(name /*%@*/).", bundle: .module)
                                  : String(localized: "\(name /*%@*/) ist überfällig.", bundle: .module))
        }
        for pot in running(schedule: schedule, finished: finished) {
            let name = pot.task.name
            let left = pot.end - minute
            parts.append(String(localized: "\(name /*%@*/) braucht noch \(left) Minuten.", bundle: .module))
        }
        if showsClock {
            let remaining = schedule.makespan - minute
            parts.append(remaining > 0 ? String(localized: "Der Plan ist in \(remaining) Minuten fertig.", bundle: .module)
                                       : String(localized: "Der Plan ist durch.", bundle: .module))
        }
        return parts.isEmpty ? String(localized: "Gerade läuft nichts.", bundle: .module) : parts.joined(separator: " ")
    }

    private func running(schedule: KitchenSchedule, finished: [String: Int]) -> [KitchenPlacement] {
        schedule.placements.filter { $0.task.unattendedMinutes > 0 && $0.handsEnd <= minute && minute < $0.end && finished[$0.id] == nil }
    }
}
