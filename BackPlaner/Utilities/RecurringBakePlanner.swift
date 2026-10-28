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

    /// Minutes a plan of the recipe takes, as `BakePlan.totalMinutes`
    /// measures it: the stored preparation time, never less than the end of
    /// the last step. The bake history records only when a plan finished;
    /// this is what turns that finish back into the plan's start.
    static func planDuration(prepTime: Int, stepEnds: [Int]) -> Int {
        max(prepTime, stepEnds.max() ?? 0)
    }

    static func planDuration(of recipe: Recipe) -> Int {
        planDuration(prepTime: recipe.prepTime,
                     stepEnds: recipe.instructionsArray.map { $0.startTime + $0.duration })
    }

    static func planDuration(of recipe: RecipeFB) -> Int {
        planDuration(prepTime: recipe.prepTime,
                     stepEnds: recipe.instructions.map { ($0.startTime ?? 0) + $0.duration })
    }

    /// The next start on the rhythm `lastStart + k·intervalDays` (`k` ≥ 1)
    /// that lies after `now`, where `lastStart` is the last plan's finish
    /// less its `duration`. The rhythm hangs on the start, so the first
    /// step — the feeding of a starter, the first mixing of a bread — comes
    /// round at the same time of day every time, whatever the recipe's
    /// length; stepping by calendar days keeps that time of day across a
    /// daylight-saving change. Stepping by whole multiples of the interval
    /// — rather than by `intervalDays` from `now` — keeps the cadence
    /// anchored to the original rhythm instead of resetting it to
    /// "whenever the app was next opened", and keeps a long-unopened app
    /// from piling up a backlog of missed cycles: it always lands on
    /// exactly one, the next due one.
    static func nextStartDate(lastFinish: Date, duration: Int, intervalDays: Int,
                              now: Date, calendar: Calendar = .current) -> Date? {
        guard intervalDays > 0,
              let lastStart = calendar.date(byAdding: .minute, value: -duration, to: lastFinish) else { return nil }

        var k = 1
        while k < 1000 {
            guard let start = calendar.date(byAdding: .day, value: intervalDays * k, to: lastStart) else {
                return nil
            }
            if start > now { return start }
            k += 1
        }
        return nil
    }

    /// The finish of the occurrence `nextStartDate` finds: its start plus
    /// the plan's `duration`.
    static func nextFinishDate(lastFinish: Date, duration: Int, intervalDays: Int,
                               now: Date, calendar: Calendar = .current) -> Date? {
        nextStartDate(lastFinish: lastFinish, duration: duration, intervalDays: intervalDays,
                      now: now, calendar: calendar)
            .flatMap { calendar.date(byAdding: .minute, value: duration, to: $0) }
    }

    /// When the rhythm next comes round, as the recipe views show it: the
    /// start of the slot the automatic pass will queue, found the same way
    /// it finds it, so the two never disagree. `nil` without a rhythm or
    /// without a bake to measure it from.
    ///
    /// A plan still pending — its bake-history entry lies ahead — is not
    /// that slot: it is already planned and sits in the list of scheduled
    /// steps. The rhythm continues after its finish. Shown as the next
    /// occurrence, a starter fed today at 17:20 on a daily rhythm read
    /// "Nächste Fütterung: Heute 17:20" where tomorrow was meant.
    static func nextStart(lastFinish: Date?, duration: Int, intervalDays: Int,
                          now: Date, calendar: Calendar = .current) -> Date? {
        guard let lastFinish else { return nil }
        return nextStartDate(lastFinish: lastFinish, duration: duration, intervalDays: intervalDays,
                             now: max(now, lastFinish), calendar: calendar)
    }

    static func nextStart(for recipe: Recipe, now: Date = Date()) -> Date? {
        nextStart(lastFinish: recipe.bakeHistoriesArray.first?.date,
                  duration: planDuration(of: recipe),
                  intervalDays: recipe.recurrenceIntervalDays, now: now)
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
                  let start = nextStartDate(lastFinish: lastFinish,
                                            duration: planDuration(of: recipe),
                                            intervalDays: recipe.recurrenceIntervalDays,
                                            now: now)
            else { continue }

            // Planned from its start, so the first step keeps its time of
            // day; the finish follows from the recipe's length.
            let plan = BakePlan(recipeName: recipe.name,
                                steps: recipe.instructionsArray.map {
                                    PlanStep(instruction: $0.instruction, step: $0.step,
                                             startTime: $0.startTime, duration: $0.duration)
                                },
                                prepTime: recipe.prepTime,
                                anchor: .startsAt,
                                date: start,
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
                                            servingScale: scale, manager: manager,
                                            isAutomaticRecurrence: true, in: context)
        }
    }

    /// How long before an automatically-queued occurrence becomes visible in
    /// the scheduled-steps views. Queuing it immediately once the rhythm is
    /// due would otherwise put it in front of the user for the recipe's full
    /// interval — a sourdough starter refreshed every 5 days would sit there
    /// for 5 days — and a reminder seen that long before it matters turns
    /// into background noise that gets overlooked.
    static let visibilityLeadTime: TimeInterval = 2 * 24 * 60 * 60
}

extension NextStep {
    /// Whether an automatically-queued step should already be shown. Steps
    /// the user planned by hand are always visible; only the ones
    /// `RecurringBakePlanner` queued ahead of time are held back.
    func isVisible(at now: Date = Date()) -> Bool {
        !isAutomaticRecurrence || date <= now.addingTimeInterval(RecurringBakePlanner.visibilityLeadTime)
    }
}
