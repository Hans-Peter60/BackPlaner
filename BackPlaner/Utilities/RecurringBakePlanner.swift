//
//  RecurringBakePlanner.swift
//  BackPlaner
//
//  Queues the next occurrence of a recipe that refreshes on a fixed rhythm
//  (a sourdough starter, say every 5 days) without anyone having to plan it
//  by hand each time. There is no background-task infrastructure in this
//  app, so the pass runs opportunistically whenever the app comes to the
//  foreground — the same moment PlanSnapshotPublisher already catches a
//  plan that moved on while the app was away.
//

import Foundation
import CoreData

enum RecurringBakePlanner {

    /// The next finish date on the rhythm `lastFinish + k·intervalDays`
    /// (`k` ≥ 1) whose plan start (finish minus `prepTime`) lies after `now`.
    /// Stepping by whole multiples of the interval — rather than by
    /// `intervalDays` from `now` — keeps the cadence anchored to the
    /// original rhythm instead of resetting it to "whenever the app was
    /// next opened", and keeps a long-unopened app from piling up a
    /// backlog of missed cycles: it always lands on exactly one, the next
    /// due one.
    static func nextFinishDate(lastFinish: Date, intervalDays: Int, prepTime: Int,
                               now: Date, calendar: Calendar = .current) -> Date? {
        guard intervalDays > 0 else { return nil }

        var k = 1
        while k < 1000 {
            guard let finish = calendar.date(byAdding: .day, value: intervalDays * k, to: lastFinish) else {
                return nil
            }
            let start = calendar.date(byAdding: .minute, value: -prepTime, to: finish) ?? finish
            if start > now { return finish }
            k += 1
        }
        return nil
    }

    /// Queues the next occurrence of every own recipe whose rhythm is due:
    /// one with `recurrenceIntervalDays > 0`, a bake history to measure the
    /// rhythm from, and no plan that is still pending. Only ever adds a
    /// plan — never replaces one, the way the manual "Jetzt planen" flow
    /// can.
    @MainActor
    static func scheduleDueOccurrences(in context: NSManagedObjectContext,
                                       manager: LocalNotificationManager = LocalNotificationManager(),
                                       now: Date = Date()) {
        let request = Recipe.fetchRequest()
        request.predicate = NSPredicate(format: "recurrenceIntervalDays > 0")
        guard let recipes = try? context.fetch(request) else { return }

        for recipe in recipes {
            guard !recipe.instructionsArray.isEmpty,
                  let lastFinish = recipe.bakeHistoriesArray.first?.date,
                  !BakePlanScheduler.hasPendingPlan(recipeName: recipe.name, now: now, in: context),
                  let finish = nextFinishDate(lastFinish: lastFinish,
                                              intervalDays: recipe.recurrenceIntervalDays,
                                              prepTime: recipe.prepTime,
                                              now: now)
            else { continue }

            let plan = BakePlan(recipeName: recipe.name,
                                steps: recipe.instructionsArray.map {
                                    PlanStep(instruction: $0.instruction, step: $0.step,
                                             startTime: $0.startTime, duration: $0.duration)
                                },
                                prepTime: recipe.prepTime,
                                anchor: .finishesBy,
                                date: finish,
                                languageCode: AppSettings.locale.identifier)

            // A conflict with another plan is left for the next foreground
            // pass to retry — there is nobody here to show an error to.
            let errors = plan.issues(in: context).filter { $0.severity == .error }
            guard errors.isEmpty else {
                AppLog.planning.notice("Automatic occurrence for \(recipe.name) skipped: \(errors.map(\.message))")
                continue
            }

            let scale = ServingScale.factor(servingSize: AppSettings.storedServingSize,
                                            targetWeight: nil, baseWeight: recipe.totalWeight)
            BakePlanScheduler.putIntoEffect(plan, for: recipe, planID: UUID(),
                                            servingScale: scale, manager: manager, in: context)
        }
    }
}
