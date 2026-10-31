//
//  CoreDataScheduledStepStore.swift
//  BackPlaner
//
//  The scheduled steps kept in Core Data as `NextStep` objects — the iOS
//  side of ScheduledStepStore. The queries are the ones the planning code
//  used to run on the context itself.
//

import BakePlannerCore
import Foundation
import CoreData

struct CoreDataScheduledStepStore: ScheduledStepStore {

    let context: NSManagedObjectContext

    func steps(excludingRecipe recipeName: String) -> [ScheduledStepData] {
        let request = NextStep.fetchRequest()
        request.predicate = NSPredicate(format: "recipeName != %@", recipeName)
        guard let steps = try? context.fetch(request) else { return [] }
        return steps.map { ScheduledStepData($0) }
    }

    func hasSteps(recipeName: String) -> Bool {
        let request = NextStep.fetchRequest()
        request.predicate = NSPredicate(format: "recipeName == %@", recipeName)
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    func hasSteps(recipeName: String, onOrAfter date: Date) -> Bool {
        let request = NextStep.fetchRequest()
        request.predicate = NSPredicate(format: "recipeName == %@ AND date >= %@", recipeName, date as NSDate)
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    func add(_ steps: [ScheduledStepData]) {
        for data in steps {
            let next = NextStep(context: context)
            next.id           = data.id
            next.planID       = data.planID
            next.recipeName   = data.recipeName
            next.servingScale = data.servingScale
            next.instruction  = data.instruction
            next.step         = data.step
            next.duration     = data.duration
            next.startTime    = data.startTime
            next.date         = data.date
            next.isAutomaticRecurrence = data.isAutomaticRecurrence
        }
        do {
            try context.save()
        } catch {
            AppLog.planning.error("Scheduled steps could not be saved: \(error.localizedDescription)")
        }
    }

    func removeSteps(recipeName: String) {
        let request = NextStep.fetchRequest()
        request.predicate = NSPredicate(format: "recipeName == %@", recipeName)
        if let previousSteps = try? context.fetch(request) {
            previousSteps.forEach { context.delete($0) }
            try? context.save()
        }
    }

    func allSteps() -> [StoredScheduledStep] {
        let request = NextStep.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true),
                                   NSSortDescriptor(key: "step", ascending: true)]
        guard let steps = try? context.fetch(request) else { return [] }
        // Keys are object IDs: steps stored before they had an id have none
        // of their own.
        return steps.map { StoredScheduledStep(key: $0.storeKey, data: ScheduledStepData($0)) }
    }

    func removeStep(key: String) {
        guard let step: NextStep = context.existingObject(storeKey: key) else { return }
        context.delete(step)
        do {
            try context.save()
        } catch {
            AppLog.planning.error("The step done could not be removed: \(error.localizedDescription)")
        }
    }
}

extension ScheduledStepData {
    init(_ step: NextStep) {
        self.init(id: step.id,
                  planID: step.planID,
                  recipeName: step.recipeName,
                  instruction: step.instruction,
                  step: step.step,
                  startTime: step.startTime,
                  duration: step.duration,
                  date: step.date,
                  isAutomaticRecurrence: step.isAutomaticRecurrence,
                  servingScale: step.servingScale)
    }
}
