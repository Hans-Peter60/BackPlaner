//
//  PlanSnapshotPublisher.swift
//  BackPlaner
//
//  Keeps the plan snapshot in the App Group container in step with the
//  planned steps in Core Data, and tells WidgetKit to reload whenever it
//  changes. One place for every path that touches the plan: setting
//  reminders, shifting, deleting, marking done from a notification, and
//  changes arriving from iCloud.
//

import BakePlannerCore
import CoreData
import WidgetKit
import os

final class PlanSnapshotPublisher {

    static let shared = PlanSnapshotPublisher()

    private var container: NSPersistentContainer?
    private var observers: [NSObjectProtocol] = []
    private var pendingRefresh: DispatchWorkItem?

    /// Starts listening for saves and remote changes of `container` and
    /// writes a first snapshot right away.
    func start(with container: NSPersistentContainer) {
        guard self.container == nil else { return }
        self.container = container

        let center = NotificationCenter.default

        // Every context of this store: the view context, the background
        // contexts of the notification actions, and the import of remote
        // changes all post this.
        observers.append(center.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: nil
        ) { [weak self] (notification: Foundation.Notification) in
            guard let self,
                  let context = notification.object as? NSManagedObjectContext,
                  context.persistentStoreCoordinator === container.persistentStoreCoordinator,
                  Self.touchesPlannedSteps(notification)
            else { return }
            self.scheduleRefresh()
        })

        // Steps planned on another device arrive through CloudKit without a
        // local save that names them, so any remote change refreshes.
        observers.append(center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            self?.scheduleRefresh()
        })

        scheduleRefresh()

        // Once per launch regardless of the data: after an app update the
        // widgets still show what the previous extension rendered until
        // their timelines are rebuilt.
        WidgetCenter.shared.reloadAllTimelines()
    }

    // `Foundation.` spelled out: the app has a `Notification` struct of its
    // own for reminders, which would shadow this one.
    private static func touchesPlannedSteps(_ notification: Foundation.Notification) -> Bool {
        for key in [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey] {
            if let objects = notification.userInfo?[key] as? Set<NSManagedObject>,
               objects.contains(where: { $0 is NextStep }) {
                return true
            }
        }
        return false
    }

    /// Coalesces bursts of saves — planning a recipe saves once per step —
    /// into a single rewrite a second later.
    private func scheduleRefresh() {
        DispatchQueue.main.async { [self] in
            pendingRefresh?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refresh() }
            pendingRefresh = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
    }

    /// Brings the Live Activity up to date and rewrites the snapshot from the
    /// store, reloading the widgets, when the plan changed. Also called when
    /// the app returns to the foreground, since that is the only time a Live
    /// Activity can be started.
    /// Carries out what was done on the widget or the Watch while the app
    /// was away: a step marked "Erledigt" there leaves the plan here,
    /// reminder included, before the snapshot is rebuilt from the plan —
    /// otherwise the rebuild would bring the step back.
    private static func applyPendingWidgetActions(in context: NSManagedObjectContext) {
        let pending = PendingWidgetActions.load()
        guard !pending.actions.isEmpty else { return }
        let request = NextStep.fetchRequest()
        // The store may still be loading when the Watch's note arrives right
        // after launch: the note stays for the next pass rather than being lost.
        guard let steps = try? context.fetch(request) else { return }
        var remaining = pending
        var removed = 0
        for action in pending.actions where action.kind == .done {
            guard let step = steps.first(where: { step in
                step.id?.uuidString == action.stepID
                    || step.objectID.uriRepresentation().absoluteString == action.stepID
            }) else { continue }
            NotificationActions.cancelPendingNotification(for: step)
            context.delete(step)
            removed += 1
            remaining.actions.removeAll { $0 == action }
        }
        // A note whose step never turned up is dropped after a week.
        remaining.actions.removeAll { Date().timeIntervalSince($0.date) > 7 * 24 * 60 * 60 }
        try? remaining.save()
        guard removed > 0 else { return }
        do {
            try context.save()
            AppLog.persistence.info("Widget: \(removed) step(s) marked done on the widget removed from the plan")
        } catch {
            context.rollback()
            AppLog.persistence.error("Widget actions could not be applied: \(error)")
        }
    }

    /// What the Watch shows under a step: the ingredients of the component
    /// the step mixes, at the plan's amount, for steps of the user's own
    /// recipes. Public recipes live in Firestore, not in this store, so
    /// their steps go without. Keyed by the step's object ID.
    private static func ingredientLines(for steps: [NextStep], in context: NSManagedObjectContext)
        -> [NSManagedObjectID: (name: String, lines: [String])] {
        var recipes: [String: RecipeExportData?] = [:]
        var result: [NSManagedObjectID: (name: String, lines: [String])] = [:]
        for step in steps {
            let content: RecipeExportData?
            if let known = recipes[step.recipeName] {
                content = known
            } else {
                let request = Recipe.fetchRequest()
                request.predicate = NSPredicate(format: "name == %@", step.recipeName)
                request.fetchLimit = 1
                content = (try? context.fetch(request))?.first.map { RecipeExportData(recipe: $0, includingImage: false) }
                recipes[step.recipeName] = content
            }
            guard let content,
                  let column = ScheduledStepComponent.column(for: content, step: step.step, instructionText: step.instruction),
                  !column.ingredients.isEmpty
            else { continue }
            result[step.objectID] = (column.name, BakeModeText.ingredientLines(of: column, scale: step.effectiveServingScale))
        }
        return result
    }

    func refresh() {
        guard let container else { return }

        let context = container.newBackgroundContext()
        context.perform {
            Self.applyPendingWidgetActions(in: context)

            let request = NextStep.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            let steps = (try? context.fetch(request)) ?? []

            // Reminders are local to the device that planned the recipe, the
            // steps are not: a plan deleted on another device only reaches
            // this one as a remote change. Every such change ends up here, so
            // the reminders that lost their step are dropped in the same pass.
            // The one-second delay above keeps a plan being created out of it:
            // its reminders are added before its steps are saved.
            NotificationActions.removeRemindersWithoutStep(
                steps.map { step in
                    NotificationActions.ScheduledNotificationMatch(
                        instruction: step.instruction,
                        date: step.date
                    )
                }
            )

            // The alarms follow the plan the same way: one per step that
            // should ring, none for a step that is gone.
            let stepData = steps.map { ScheduledStepData($0) }
            DispatchQueue.main.async {
                BakeAlarmManager.shared.sync(steps: stepData)
            }

            // Automatically-queued recurring steps more than
            // RecurringBakePlanner.visibilityLeadTime away stay out of the
            // snapshot, so the widget and Live Activity don't pick them up
            // as "Als Nächstes" long before they're due. Reminders are kept
            // for all steps above — they still have to fire on time.
            let visible = steps.filter { $0.isVisible() }
            let ingredients = Self.ingredientLines(for: visible, in: context)
            let snapshot = PlanSnapshot(
                steps: visible.map { step in
                    let component = ingredients[step.objectID]
                    return PlanSnapshot.Step(
                        id: step.id?.uuidString ?? step.objectID.uriRepresentation().absoluteString,
                        recipeName: step.recipeName,
                        instruction: step.instruction,
                        date: step.date,
                        duration: step.duration,
                        componentName: component?.name,
                        ingredientLines: component?.lines
                    )
                },
                generatedAt: Date()
            )

            // The Live Activity depends on the time as well as the data, so
            // it is brought up to date on every pass, changed plan or not.
            DispatchQueue.main.async {
                BakeActivityManager.shared.refresh(with: snapshot)
            }

            if let existing = PlanSnapshot.load(), existing.steps == snapshot.steps {
                return
            }

            do {
                try snapshot.save()
                WidgetCenter.shared.reloadAllTimelines()
                WatchPlanSync.shared.send(snapshot)
                AppLog.persistence.debug("Plan snapshot written with \(snapshot.steps.count) steps")
            } catch {
                AppLog.persistence.error("Could not write plan snapshot: \(error)")
            }
        }
    }
}
