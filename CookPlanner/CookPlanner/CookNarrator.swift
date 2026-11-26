//
//  CookNarrator.swift
//  CookPlanner
//
//  The sentences the cook mode says, and Siri repeats: what is in the
//  hands, what comes next, how long. Built from a plan, the live schedule
//  and the ticks, so the view and the App Intents word things the same.
//

import BakePlannerCore
import Foundation

struct CookNarrator {
    let plan: DishPlan
    let schedule: KitchenSchedule
    let finished: [String: Int]
    let handsDone: [String: Int]
    /// False in the relaxed mode: no minutes, nothing overdue, and the
    /// next ready step comes forward as soon as the hands are free.
    let showsClock: Bool
    let locale: Locale
    let minute: Int

    private var placements: [KitchenPlacement] { schedule.placements }

    /// The steps in the hands right now, as the screen shows them. Relaxed:
    /// nobody waits for the plan's minute — once the hands are free, the
    /// next step whose predecessors are done or ran out comes forward; only
    /// a pot still cooking holds its followers back.
    var handsNow: [KitchenPlacement] {
        let inHands = placements.filter { placement in
            placement.task.handsMinutes > 0 && placement.start <= minute && finished[placement.id] == nil
                && handsDone[placement.id] == nil
                && (placement.task.unattendedMinutes == 0 || minute < placement.handsEnd)
        }
        if !inHands.isEmpty || showsClock { return inHands }
        let upcoming = placements.filter { $0.start > minute }.sorted { ($0.start, $0.task.id) < ($1.start, $1.task.id) }
        return upcoming.first { candidate in
            candidate.task.handsMinutes > 0 && candidate.task.after.allSatisfy { id in
                finished[id] != nil || placements.contains { $0.id == id && $0.task.handsMinutes == 0 && $0.end <= minute }
                    || placements.contains { $0.id == id && $0.task.unattendedMinutes > 0 && $0.end <= minute }
            }
        }.map { [$0] } ?? []
    }

    /// Pots and oven steps running on their own right now.
    var running: [KitchenPlacement] {
        placements.filter { $0.task.unattendedMinutes > 0 && $0.handsEnd <= minute && minute < $0.end && finished[$0.id] == nil }
    }

    /// A step for the ear: component, name, ingredients, oven, and how long.
    func stepSentence(_ placement: KitchenPlacement) -> String {
        let task = placement.task
        var parts = [String]()
        parts.append(task.component.isEmpty ? task.name + "." : task.component + ": " + task.name + ".")
        let ingredients = plan.dish.ingredients(for: task)
        if !ingredients.isEmpty {
            parts.append(KitchenSpokenText.lines(for: ingredients, locale: locale) + ".")
        }
        if let temperature = task.ovenTemperature {
            parts.append(String(format: spoken("Ofen %lld Grad."), Int64(temperature)))
        }
        if showsClock && task.handsMinutes > 0 {
            let left = placement.start + task.handsMinutes - minute
            parts.append(left > 0 ? String(format: spoken("%lld Minuten."), Int64(left)) : spoken("Überfällig."))
        }
        if task.unattendedMinutes > 0 {
            parts.append(String(format: spoken("Dann %lld Minuten von allein."), Int64(task.unattendedMinutes)))
        }
        return parts.joined(separator: " ")
    }

    /// What is in the hands, or what the hands wait for.
    func now() -> String {
        if let step = handsNow.first { return stepSentence(step) }
        let rest = followUp(after: nil, always: true)
        return spoken("Gerade ist nichts in der Hand.") + " " + rest
    }

    /// What comes after `id`: the next step in the hands, read aloud — or
    /// what the hands wait for. Empty when nothing follows and `always` is
    /// off, so a confirmation stays short.
    func followUp(after id: String?, always: Bool = false) -> String {
        let current = handsNow.filter { $0.id != id }
        if let next = current.first {
            return spoken("Jetzt:") + " " + stepSentence(next)
        }
        let upcoming = placements.filter { $0.start > minute && $0.task.handsMinutes > 0 && $0.id != id }
            .sorted { ($0.start, $0.task.id) < ($1.start, $1.task.id) }
        if let next = upcoming.first {
            let wait = next.start - minute
            return showsClock
                ? String(format: spoken("Gleich, in %lld Minuten: %@."), Int64(wait), next.task.name)
                : String(format: spoken("Gleich: %@."), next.task.name)
        }
        if let pot = running.min(by: { $0.end < $1.end }) {
            return String(format: spoken("%@ braucht noch %lld Minuten."), pot.task.name, Int64(pot.end - minute))
        }
        return always ? spoken("Das war der letzte Schritt. Fertig, anrichten!") : ""
    }

    /// The time left on the step in the hands, on every pot, and on the plan.
    func timing() -> String {
        var parts = [String]()
        if let current = handsNow.first, showsClock {
            let left = current.start + current.task.handsMinutes - minute
            parts.append(left > 0 ? String(format: spoken("Noch %lld Minuten für %@."), Int64(left), current.task.name)
                                  : String(format: spoken("%@ ist überfällig."), current.task.name))
        }
        for pot in running {
            parts.append(String(format: spoken("%@ braucht noch %lld Minuten."), pot.task.name, Int64(pot.end - minute)))
        }
        if showsClock {
            let remaining = schedule.makespan - minute
            parts.append(remaining > 0 ? String(format: spoken("Der Plan ist in %lld Minuten fertig."), Int64(remaining))
                                       : spoken("Der Plan ist durch."))
        }
        return parts.isEmpty ? spoken("Gerade läuft nichts.") : parts.joined(separator: " ")
    }

    /// A sentence the app says, in the app's language.
    func spoken(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }
}
