//
//  BakePlanScheduler.swift
//  BackPlaner
//
//  The part of planning that touches the device: the reminders, the
//  scheduled steps and bake-history entries in Core Data, and the queries
//  for plans already scheduled. Kept apart from BakePlan, BakePlanValidator,
//  BakePlanAdvisor and RecurringBakePlanner, which only calculate, so those
//  can later move into a platform-neutral package unchanged.
//

import Foundation
import CoreData

/// Puts a `BakePlan` into effect: the reminders and the scheduled steps.
struct BakePlanScheduler {

    let plan: BakePlan
    /// Identifies the plan's reminders: the recipe's reminder id and the plan
    /// id, so two plans of one recipe never replace each other's reminders.
    let reminderID: String
    var manager = LocalNotificationManager()

    struct Result {
        /// The recipe's steps plus the generated ones.
        let reminderCount: Int
        /// When the oven is switched on; nil for a plan without a bake, such
        /// as feeding a starter.
        let ovenOnDate: Date?
        let finishDate: Date
        /// "250 °C", if the recipe states an oven temperature.
        let ovenTemperature: String?
    }

    /// Sets a reminder for every step. `details` gives the extra text of the
    /// recipe step at that index (the ingredients a step mixes); generated
    /// steps have none.
    func scheduleReminders(details: (Int) -> String?) -> Result {
        for (index, step) in plan.scheduledSteps.enumerated() {
            _ = manager.setNotification(reminderID, step.instruction,
                                        Rational.decimalPlace(step.step, 10),
                                        plan.reminderOffset(of: step), plan.date, true,
                                        details: details(index))
        }

        let generatedSteps = [plan.generatedOvenStep, plan.generatedTurnDownStep].compactMap { $0 }
        for generated in generatedSteps {
            _ = manager.setNotification(reminderID, generated.instruction,
                                        Rational.decimalPlace(generated.step, 10),
                                        plan.reminderOffset(of: generated), plan.date, true)
        }

        let endStep = plan.endStep
        let finishDate = manager.setNotification(reminderID, endStep.instruction, "99",
                                                 plan.reminderOffset(of: endStep), plan.date, true)

        return Result(reminderCount: plan.steps.count + generatedSteps.count + 1,
                      ovenOnDate: plan.ovenOnStep.map(plan.date(of:)),
                      finishDate: finishDate,
                      ovenTemperature: plan.ovenTemperature)
    }

    /// Writes every step of the plan as a scheduled step. `servingScale` is
    /// the factor the plan was made at, so the plan's ingredient lists show
    /// the amounts that are actually weighed out. `isAutomaticRecurrence`
    /// marks steps queued by `RecurringBakePlanner` rather than by the user, so
    /// the scheduled-steps views can hold them back until shortly before they're due.
    func writeScheduledSteps(planID: UUID, servingScale: Double, isAutomaticRecurrence: Bool = false,
                             to store: any ScheduledStepStore) {
        store.add(plan.scheduledStepData(planID: planID, servingScale: servingScale,
                                         isAutomaticRecurrence: isAutomaticRecurrence))
    }

    func writeScheduledSteps(planID: UUID, servingScale: Double, isAutomaticRecurrence: Bool = false, in context: NSManagedObjectContext) {
        writeScheduledSteps(planID: planID, servingScale: servingScale,
                            isAutomaticRecurrence: isAutomaticRecurrence,
                            to: CoreDataScheduledStepStore(context: context))
    }

    /// Whether the recipe already has scheduled steps.
    static func hasPlan(recipeName: String, from store: any ScheduledStepStore) -> Bool {
        store.hasSteps(recipeName: recipeName)
    }

    static func hasPlan(recipeName: String, in context: NSManagedObjectContext) -> Bool {
        hasPlan(recipeName: recipeName, from: CoreDataScheduledStepStore(context: context))
    }

    /// Whether the recipe has a plan that is not over yet — a step still
    /// pending or in progress. Used to keep the automatic recurrence pass
    /// from queuing a second occurrence beside one that already covers the
    /// recipe's next due date.
    static func hasPendingPlan(recipeName: String, now: Date = Date(),
                               from store: any ScheduledStepStore) -> Bool {
        store.hasSteps(recipeName: recipeName, onOrAfter: now)
    }

    static func hasPendingPlan(recipeName: String, now: Date = Date(),
                               in context: NSManagedObjectContext) -> Bool {
        hasPendingPlan(recipeName: recipeName, now: now, from: CoreDataScheduledStepStore(context: context))
    }

    /// Reminders, scheduled steps and the bake-history entry for one plan —
    /// the part of scheduling a recipe that has nothing to do with the UI
    /// that triggered it. Shared by the manual "Jetzt planen" flow
    /// (`InstructionsView`) and the automatic recurrence pass
    /// (`RecurringBakePlanner`), so the two can't drift apart.
    @discardableResult
    static func putIntoEffect(_ plan: BakePlan, for recipe: Recipe, planID: UUID,
                              servingScale: Double, manager: LocalNotificationManager,
                              isAutomaticRecurrence: Bool = false,
                              in context: NSManagedObjectContext) -> Result {
        recipe.bakeHistoryFlag = true

        let instructions = recipe.instructionsArray
        let scheduler = BakePlanScheduler(plan: plan,
                                          reminderID: "\(recipe.reminderId)-\(planID.uuidString)",
                                          manager: manager)
        let result = scheduler.scheduleReminders { index in
            let instruction = instructions[index]
            return ScheduledStepComponent.column(for: recipe,
                                                 instruction: instruction,
                                                 instructionText: instruction.instruction)
                .flatMap { ScheduledStepComponent.ingredientsText(for: $0, scale: servingScale) }
        }
        scheduler.writeScheduledSteps(planID: planID, servingScale: servingScale,
                                      isAutomaticRecurrence: isAutomaticRecurrence, in: context)

        // The bake history gets an entry for the end of this bake.
        let bakeHistory     = BakeHistory(context: context)
        bakeHistory.date    = result.finishDate
        bakeHistory.comment = AppSettings.generatedRecipeTexts().missingComment
        recipe.addToBakeHistories(bakeHistory)
        context.performAndWait {
            try? context.save()
        }

        return result
    }

    /// Drops every earlier plan of a recipe, its scheduled steps and their
    /// reminders, before a replacing plan is written. The reminders are
    /// matched by identifier prefix, which the new plan's id keeps out of:
    /// cancelling runs asynchronously and would otherwise catch the reminders
    /// being created right now.
    static func removePlans(recipeName: String, reminderPrefix: String,
                            keeping planID: UUID, in context: NSManagedObjectContext) {
        removePlans(recipeName: recipeName, reminderPrefix: reminderPrefix, keeping: planID,
                    from: CoreDataScheduledStepStore(context: context))
    }

    static func removePlans(recipeName: String, reminderPrefix: String,
                            keeping planID: UUID, from store: any ScheduledStepStore) {
        store.removeSteps(recipeName: recipeName)
        NotificationActions.cancelPendingNotifications(withIdentifierPrefix: "Recipe-\(reminderPrefix)-",
                                                       excludingContaining: planID.uuidString)
    }
}

// MARK: - Plan checks against the scheduled plans in Core Data

extension BakePlan {
    func issues(in context: NSManagedObjectContext) -> [BakePlanIssue] {
        issues(from: CoreDataScheduledStepStore(context: context))
    }
}

extension BakePlanValidator {
    static func scheduledBakeWindows(
        excluding recipeName: String,
        in context: NSManagedObjectContext,
        now: Date = Date()
    ) -> [BakeWindow] {
        scheduledBakeWindows(excluding: recipeName, from: CoreDataScheduledStepStore(context: context), now: now)
    }
}

extension BakePlanAdvisor {
    static func nightFreeDates(for plan: BakePlan, in context: NSManagedObjectContext,
                               now: Date = Date()) -> [NightFreeDate] {
        nightFreeDates(for: plan, from: CoreDataScheduledStepStore(context: context), now: now)
    }
}

// MARK: - Recurring plans

extension RecurringBakePlanner {
    static func planDuration(of recipe: Recipe) -> Int {
        planDuration(prepTime: recipe.prepTime,
                     stepEnds: recipe.instructionsArray.map { $0.startTime + $0.duration })
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
}

extension NextStep {
    /// Whether an automatically-queued step should already be shown. Steps
    /// the user planned by hand are always visible; only the ones
    /// `RecurringBakePlanner` queued ahead of time are held back.
    func isVisible(at now: Date = Date()) -> Bool {
        !isAutomaticRecurrence || date <= now.addingTimeInterval(RecurringBakePlanner.visibilityLeadTime)
    }
}
