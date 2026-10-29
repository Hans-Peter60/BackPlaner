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
    func writeScheduledSteps(planID: UUID, servingScale: Double, isAutomaticRecurrence: Bool = false, in context: NSManagedObjectContext) {
        for step in plan.allSteps {
            let next = NextStep(context: context)
            next.id           = UUID()
            next.planID       = planID
            next.recipeName   = plan.recipeName
            next.servingScale = servingScale
            next.instruction = step.instruction
            next.step        = step.step
            next.duration    = step.duration
            next.startTime   = step.startTime
            next.date        = plan.date(of: step)
            next.isAutomaticRecurrence = isAutomaticRecurrence
        }
        do {
            try context.save()
        } catch {
            AppLog.planning.error("Scheduled steps could not be saved: \(error.localizedDescription)")
        }
    }

    /// Whether the recipe already has scheduled steps.
    static func hasPlan(recipeName: String, in context: NSManagedObjectContext) -> Bool {
        let request = NextStep.fetchRequest()
        request.predicate = NSPredicate(format: "recipeName == %@", recipeName)
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    /// Whether the recipe has a plan that is not over yet — a step still
    /// pending or in progress. Used to keep the automatic recurrence pass
    /// from queuing a second occurrence beside one that already covers the
    /// recipe's next due date.
    static func hasPendingPlan(recipeName: String, now: Date = Date(),
                               in context: NSManagedObjectContext) -> Bool {
        let request = NextStep.fetchRequest()
        request.predicate = NSPredicate(format: "recipeName == %@ AND date >= %@", recipeName, now as NSDate)
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
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
        let request = NextStep.fetchRequest()
        request.predicate = NSPredicate(format: "recipeName == %@", recipeName)
        if let previousSteps = try? context.fetch(request) {
            previousSteps.forEach { context.delete($0) }
            try? context.save()
        }
        NotificationActions.cancelPendingNotifications(withIdentifierPrefix: "Recipe-\(reminderPrefix)-",
                                                       excludingContaining: planID.uuidString)
    }
}

// MARK: - Plan checks against the scheduled plans

extension BakePlan {
    func issues(in context: NSManagedObjectContext) -> [BakePlanIssue] {
        issues(existingWindows: BakePlanValidator.scheduledBakeWindows(excluding: recipeName, in: context))
    }
}

extension BakePlanValidator {
    /// The oven phases of all plans that are currently scheduled, without the
    /// plan of `recipeName` (which is about to be replaced) and without bakes
    /// that are already over.
    static func scheduledBakeWindows(
        excluding recipeName: String,
        in context: NSManagedObjectContext,
        now: Date = Date()
    ) -> [BakeWindow] {

        let request = NextStep.fetchRequest()
        request.predicate = NSPredicate(format: "recipeName != %@", recipeName)

        guard let steps = try? context.fetch(request) else { return [] }

        return Dictionary(grouping: steps, by: \.recipeName)
            .compactMap { name, steps in
                bakeWindow(
                    recipeName: name,
                    steps: steps.map {
                        PlannedStep(instruction: $0.instruction, step: $0.step, date: $0.date)
                    }
                )
            }
            .filter { $0.end > now }
    }
}

extension BakePlanAdvisor {
    /// The suggestions for the baking views: the day window from the
    /// settings, nothing before now or beyond the picker's range, and the
    /// bakes already scheduled.
    static func nightFreeDates(for plan: BakePlan, in context: NSManagedObjectContext,
                               now: Date = Date()) -> [NightFreeDate] {
        let (dayStart, dayEnd) = BakePlanValidator.dayWindow()
        let range = GlobalVariables.planningDateRange(around: now)
        guard now < range.upperBound else { return [] }
        return nightFreeDates(
            for: plan, dayStart: dayStart, dayEnd: dayEnd,
            allowedDates: now...range.upperBound,
            existingWindows: BakePlanValidator.scheduledBakeWindows(excluding: plan.recipeName, in: context),
            ovenCount: GlobalVariables.ovenCount
        )
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
