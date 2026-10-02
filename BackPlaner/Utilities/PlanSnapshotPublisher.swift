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
    func refresh() {
        guard let container else { return }

        let context = container.newBackgroundContext()
        context.perform {
            let request = NextStep.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            let steps = (try? context.fetch(request)) ?? []

            let snapshot = PlanSnapshot(
                steps: steps.map { step in
                    PlanSnapshot.Step(
                        id: step.id?.uuidString ?? step.objectID.uriRepresentation().absoluteString,
                        recipeName: step.recipeName,
                        instruction: step.instruction,
                        date: step.date,
                        duration: step.duration
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
                AppLog.persistence.debug("Plan snapshot written with \(snapshot.steps.count) steps")
            } catch {
                AppLog.persistence.error("Could not write plan snapshot: \(error)")
            }
        }
    }
}
