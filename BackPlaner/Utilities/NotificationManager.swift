//
//  NotificationManager.swift
//  PetersBackplaner
//
//  Created by Hans-Peter Müller on 09.11.21.
//

import Foundation
import CoreData
import UserNotifications
import os

struct DateCalculation {
    
    let formatter = DateFormatter()
    
    func calculateDateTime(dT: Date) -> String {
        
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = AppSettings.locale
        return formatter.string(from: dT)
    }
}

struct TimeCalculation {
    
    let formatter = DateFormatter()
    
    func calculateTime(t: Date) -> String {
        
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = AppSettings.locale
        return formatter.string(from: t)
    }
}

class LocalNotificationManager: ObservableObject {
    
    @Published var notifications = [Notification]()
    
    func setNotification(_ id:String, _ instruction: String, _ step: String, _ startTime: Int, _ date: Date, _ shouldScheduleNotifications: Bool) -> Date {
        
        var calcDate = date
        
        notifications = [Notification]()
 
        calcDate = Calendar.current.date(byAdding: .minute, value: startTime, to: calcDate) ?? calcDate
        
        let dateComponents = Calendar.current.dateComponents(in: .current, from: calcDate)
        let year   = dateComponents.year
        let month  = dateComponents.month
        let day    = dateComponents.day
        let hour   = dateComponents.hour
        let minute = dateComponents.minute

        notifications.append(
            Notification(
                id: "Recipe-\(id)-\(step)",
                recipeID: id,
                step: step,
                title: instruction,
                date: calcDate,
                datetime: DateComponents(
                    calendar: Calendar.current,
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        )
               
        if shouldScheduleNotifications {
            scheduleNotifications()
        }
        
        return calcDate
    }
  
    private func scheduleNotifications() {
        
        for notification in notifications {
            
            let content      = UNMutableNotificationContent()
            content.title              = String(localized: "Backhinweis", locale: AppSettings.locale)
            content.subtitle           = String(localized: "Gedrückt halten für Erledigt oder Verschieben", locale: AppSettings.locale)
            content.body               = notification.title
            content.sound              = .default
            content.categoryIdentifier = NotificationActions.reminderCategory
            content.threadIdentifier   = notification.recipeID
            content.userInfo = [
                NotificationActions.recipeIDKey: notification.recipeID,
                NotificationActions.instructionKey: notification.title,
                NotificationActions.stepKey: notification.step,
                NotificationActions.scheduledDateKey: notification.date.timeIntervalSince1970
            ]
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: notification.datetime, repeats: false)
            
            let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request) { error in
                
                guard error == nil else { return }

                AppLog.notifications.debug("Notification scheduled! --- ID = \(notification.id) \(notification.datetime)")
            }
        }
    }
    
    func listScheduledNotifications() {
        
        AppLog.notifications.debug("Anfrage der pending Notifications")
        UNUserNotificationCenter.current().getPendingNotificationRequests { notifications in

            for notification in notifications {
                AppLog.notifications.debug("\(String(describing: notification))")
            }
        }
    }
    
    func requestAuthorization() {
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            
            if granted == true && error == nil {
                self.scheduleNotifications()
            }
        }
    }
    
    func schedule() {
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            
            switch settings.authorizationStatus {
            case .notDetermined:
                self.requestAuthorization()
            case .authorized, .provisional:
                self.scheduleNotifications()
            default:
                break // Do nothing
            }
        }
    }
}

struct Notification: Identifiable {
    var id: String
    var recipeID: String
    var step: String
    var title: String
    var date: Date
    var datetime: DateComponents
}

enum NotificationActions {
    static let reminderCategory = "BAKING_REMINDER"
    static let postponementCategory = "BAKING_POSTPONEMENT_CONFIRMATION"

    static let doneAction = "BAKING_DONE"
    static let postponeAction = "BAKING_POSTPONE"
    static let postponeOnlyAction = "BAKING_POSTPONE_ONLY"
    static let postponeFollowingAction = "BAKING_POSTPONE_FOLLOWING"

    static let recipeIDKey = "recipeID"
    static let instructionKey = "instruction"
    static let stepKey = "step"
    static let scheduledDateKey = "scheduledDate"
    static let minutesKey = "postponeMinutes"
    static let originalIdentifierKey = "originalIdentifier"

    static func registerCategories() {
        let done = UNNotificationAction(
            identifier: doneAction,
            title: String(localized: "Erledigt", locale: AppSettings.locale),
            options: []
        )
        let postpone = UNTextInputNotificationAction(
            identifier: postponeAction,
            title: String(localized: "Verschieben um …", locale: AppSettings.locale),
            options: [],
            textInputButtonTitle: String(localized: "Verschieben", locale: AppSettings.locale),
            textInputPlaceholder: String(localized: "Minuten", locale: AppSettings.locale)
        )
        let reminder = UNNotificationCategory(
            identifier: reminderCategory,
            actions: [done, postpone],
            intentIdentifiers: []
        )

        let postponeOnly = UNNotificationAction(
            identifier: postponeOnlyAction,
            title: String(localized: "Nur diesen Schritt", locale: AppSettings.locale),
            options: []
        )
        let postponeFollowing = UNNotificationAction(
            identifier: postponeFollowingAction,
            title: String(localized: "Alle nachfolgenden", locale: AppSettings.locale),
            options: []
        )
        let confirmation = UNNotificationCategory(
            identifier: postponementCategory,
            actions: [postponeOnly, postponeFollowing],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([reminder, confirmation])
    }

    static func handle(
        response: UNNotificationResponse,
        completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case doneAction:
            markDone(userInfo: response.notification.request.content.userInfo)
            completionHandler()

        case postponeAction:
            guard let textResponse = response as? UNTextInputNotificationResponse,
                  let minutes = firstPositiveInteger(in: textResponse.userText) else {
                completionHandler()
                return
            }
            requestPostponementConfirmation(
                for: response.notification.request,
                minutes: min(minutes, 1_440),
                completionHandler: completionHandler
            )

        case postponeOnlyAction:
            applyPostponement(
                from: response.notification.request.content,
                includeFollowing: false,
                completionHandler: completionHandler
            )

        case postponeFollowingAction:
            applyPostponement(
                from: response.notification.request.content,
                includeFollowing: true,
                completionHandler: completionHandler
            )

        default:
            completionHandler()
        }
    }

    private static func firstPositiveInteger(in text: String) -> Int? {
        let digits = text.split(whereSeparator: { !$0.isNumber }).first
        guard let digits, let value = Int(digits), value > 0 else { return nil }
        return value
    }

    private static func requestPostponementConfirmation(
        for originalRequest: UNNotificationRequest,
        minutes: Int,
        completionHandler: @escaping () -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Reminder verschieben", locale: AppSettings.locale)
        content.body = String(
            localized: "Sollen alle nachfolgenden Schritte dieses Rezepts ebenfalls verschoben werden?",
            locale: AppSettings.locale
        )
        content.sound = .default
        content.categoryIdentifier = postponementCategory
        content.threadIdentifier = originalRequest.content.threadIdentifier

        var userInfo = originalRequest.content.userInfo
        userInfo[minutesKey] = minutes
        userInfo[originalIdentifierKey] = originalRequest.identifier
        userInfo[instructionKey] = originalRequest.content.body
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: "Postponement-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLog.notifications.error("Could not request postponement confirmation: \(error)")
            }
            completionHandler()
        }
    }

    private static func markDone(userInfo: [AnyHashable: Any]) {
        guard let metadata = metadata(from: userInfo) else { return }

        // Use the view context so active list and timeline fetch requests immediately
        // observe the deletion after the notification action.
        let context = PersistenceController.shared.container.viewContext
        context.perform {
            guard let step = fetchCurrentStep(metadata: metadata, in: context) else {
                AppLog.persistence.error("Could not find scheduled step to mark as done")
                return
            }

            context.delete(step)
            do {
                try context.save()
            } catch {
                context.rollback()
                AppLog.persistence.error("Could not mark scheduled step as done: \(error)")
            }
        }
    }

    private static func applyPostponement(
        from content: UNNotificationContent,
        includeFollowing: Bool,
        completionHandler: @escaping () -> Void
    ) {
        guard let metadata = metadata(from: content.userInfo),
              let minutes = integerValue(content.userInfo[minutesKey]),
              let originalIdentifier = content.userInfo[originalIdentifierKey] as? String else {
            completionHandler()
            return
        }

        let newCurrentDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let shift = newCurrentDate.timeIntervalSince(metadata.scheduledDate)
        let context = PersistenceController.shared.container.newBackgroundContext()

        context.perform {
            let currentStep = fetchCurrentStep(metadata: metadata, in: context)
            let recipeName = currentStep?.recipeName

            if let currentStep {
                currentStep.date = newCurrentDate
            }

            if includeFollowing, let recipeName {
                let request = NextStep.fetchRequest()
                request.predicate = NSPredicate(
                    format: "recipeName == %@ AND date > %@",
                    recipeName,
                    metadata.scheduledDate as NSDate
                )
                if let followingSteps = try? context.fetch(request) {
                    for step in followingSteps {
                        step.date = step.date.addingTimeInterval(shift)
                    }
                }
            }

            do {
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                AppLog.persistence.error("Could not postpone scheduled steps: \(error)")
            }

            rescheduleNotifications(
                originalContent: content,
                originalIdentifier: originalIdentifier,
                metadata: metadata,
                newCurrentDate: newCurrentDate,
                shift: shift,
                includeFollowing: includeFollowing,
                completionHandler: completionHandler
            )
        }
    }

    private static func rescheduleNotifications(
        originalContent: UNNotificationContent,
        originalIdentifier: String,
        metadata: ReminderMetadata,
        newCurrentDate: Date,
        shift: TimeInterval,
        includeFollowing: Bool,
        completionHandler: @escaping () -> Void
    ) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            var requestsToReplace = requests.filter { request in
                guard includeFollowing,
                      let recipeID = request.content.userInfo[recipeIDKey] as? String,
                      recipeID == metadata.recipeID,
                      let date = dateValue(request.content.userInfo[scheduledDateKey]) else {
                    return false
                }
                return date > metadata.scheduledDate
            }

            if let currentRequest = postponedRequest(
                identifier: originalIdentifier,
                content: originalContent,
                date: newCurrentDate
            ) {
                requestsToReplace.append(currentRequest)
            }

            let identifiers = requestsToReplace
                .map(\.identifier)
                .filter { $0 != originalIdentifier }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)

            let group = DispatchGroup()
            for request in requestsToReplace {
                let replacement: UNNotificationRequest?
                if request.identifier == originalIdentifier {
                    replacement = request
                } else if let date = dateValue(request.content.userInfo[scheduledDateKey]) {
                    replacement = postponedRequest(
                        identifier: request.identifier,
                        content: request.content,
                        date: date.addingTimeInterval(shift)
                    )
                } else {
                    replacement = nil
                }

                guard let replacement else { continue }
                group.enter()
                center.add(replacement) { error in
                    if let error {
                        AppLog.notifications.error("Could not postpone notification: \(error)")
                    }
                    group.leave()
                }
            }

            group.notify(queue: .global()) {
                completionHandler()
            }
        }
    }

    private static func postponedRequest(
        identifier: String,
        content: UNNotificationContent,
        date: Date
    ) -> UNNotificationRequest? {
        guard let mutableContent = content.mutableCopy() as? UNMutableNotificationContent else {
            return nil
        }
        mutableContent.title = String(localized: "Backhinweis", locale: AppSettings.locale)
        if let instruction = mutableContent.userInfo[instructionKey] as? String {
            mutableContent.body = instruction
        }
        mutableContent.categoryIdentifier = reminderCategory
        mutableContent.userInfo[scheduledDateKey] = date.timeIntervalSince1970
        mutableContent.userInfo.removeValue(forKey: minutesKey)
        mutableContent.userInfo.removeValue(forKey: originalIdentifierKey)

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return UNNotificationRequest(
            identifier: identifier,
            content: mutableContent,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    /// Cancels the pending reminder that belongs to a scheduled step, so a
    /// reminder never outlives the step it was created for.
    ///
    /// The step does not store its notification identifier, so the request is
    /// matched the same way `shiftPendingNotifications` does it: by instruction
    /// text and scheduled date. Read the step's properties before calling this —
    /// they are captured synchronously, so the object may be deleted right after.
    static func cancelPendingNotification(for step: NextStep) {
        let match = ScheduledNotificationMatch(
            instruction: step.instruction,
            date: step.date
        )
        let center = UNUserNotificationCenter.current()

        center.getPendingNotificationRequests { requests in
            let identifiers = requests.filter { request in
                guard let requestInstruction = request.content.userInfo[instructionKey] as? String,
                      let requestDate = dateValue(request.content.userInfo[scheduledDateKey]) else {
                    return false
                }
                return requestInstruction == match.instruction
                    && abs(requestDate.timeIntervalSince(match.date)) <= 60
            }
            .map(\.identifier)

            guard !identifiers.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    /// Cancels the pending reminders of several scheduled steps in a single
    /// pass, used when all steps of one recipe are removed from the plan.
    ///
    /// Matching works exactly like `cancelPendingNotification(for:)`. The step
    /// properties are read synchronously, so the objects may be deleted right
    /// after the call returns.
    static func cancelPendingNotifications(for steps: [NextStep]) {
        let matches = steps.map { step in
            ScheduledNotificationMatch(instruction: step.instruction, date: step.date)
        }
        guard !matches.isEmpty else { return }

        let center = UNUserNotificationCenter.current()

        center.getPendingNotificationRequests { requests in
            let identifiers = requests.filter { request in
                guard let requestInstruction = request.content.userInfo[instructionKey] as? String,
                      let requestDate = dateValue(request.content.userInfo[scheduledDateKey]) else {
                    return false
                }
                return matches.contains { match in
                    requestInstruction == match.instruction
                        && abs(requestDate.timeIntervalSince(match.date)) <= 60
                }
            }
            .map(\.identifier)

            guard !identifiers.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    static func shiftScheduledStep(
        _ step: NextStep,
        byMinutes minutes: Int,
        includeFollowing: Bool,
        completionHandler: @escaping (Result<Void, Error>) -> Void
    ) {
        let timeShift = TimeInterval(minutes * 60)
        let originalDate = step.date
        let recipeName = step.recipeName
        let instruction = step.instruction
        let shiftedDate = originalDate.addingTimeInterval(timeShift)

        guard shiftedDate > Date() else {
            completionHandler(.failure(ScheduledStepShiftError.dateInPast))
            return
        }

        let context = step.managedObjectContext
        context?.perform {
            var notificationMatches = [
                ScheduledNotificationMatch(instruction: instruction, date: originalDate)
            ]
            step.date = shiftedDate

            if includeFollowing, let context {
                let request = NextStep.fetchRequest()
                request.predicate = NSPredicate(
                    format: "recipeName == %@ AND date > %@",
                    recipeName,
                    originalDate as NSDate
                )
                if let followingSteps = try? context.fetch(request) {
                    for followingStep in followingSteps {
                        notificationMatches.append(
                            ScheduledNotificationMatch(
                                instruction: followingStep.instruction,
                                date: followingStep.date
                            )
                        )
                        followingStep.date = followingStep.date.addingTimeInterval(timeShift)
                    }
                }
            }

            do {
                try context?.save()
            } catch {
                context?.rollback()
                completionHandler(.failure(error))
                return
            }

            shiftPendingNotifications(
                recipeName: recipeName,
                matches: notificationMatches,
                timeShift: timeShift,
                completionHandler: completionHandler
            )
        }
    }

    private static func shiftPendingNotifications(
        recipeName: String,
        matches: [ScheduledNotificationMatch],
        timeShift: TimeInterval,
        completionHandler: @escaping (Result<Void, Error>) -> Void
    ) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            var usedIdentifiers = Set<String>()
            var replacements = [UNNotificationRequest]()

            for match in matches {
                let existingRequest = requests.first { request in
                    guard !usedIdentifiers.contains(request.identifier),
                          let date = dateValue(request.content.userInfo[scheduledDateKey]),
                          let requestInstruction = request.content.userInfo[instructionKey] as? String else {
                        return false
                    }
                    return requestInstruction == match.instruction
                        && abs(date.timeIntervalSince(match.date)) <= 60
                }

                let newDate = match.date.addingTimeInterval(timeShift)
                if let existingRequest,
                   let replacement = postponedRequest(
                       identifier: existingRequest.identifier,
                       content: existingRequest.content,
                       date: newDate
                   ) {
                    usedIdentifiers.insert(existingRequest.identifier)
                    replacements.append(replacement)
                } else {
                    replacements.append(
                        newReminderRequest(
                            recipeName: recipeName,
                            instruction: match.instruction,
                            date: newDate
                        )
                    )
                }
            }

            center.removePendingNotificationRequests(
                withIdentifiers: Array(usedIdentifiers)
            )

            let group = DispatchGroup()
            var firstError: Error?
            for replacement in replacements {
                group.enter()
                center.add(replacement) { error in
                    if firstError == nil {
                        firstError = error
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                if let firstError {
                    completionHandler(.failure(firstError))
                } else {
                    completionHandler(.success(()))
                }
            }
        }
    }

    private static func newReminderRequest(
        recipeName: String,
        instruction: String,
        date: Date
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Backhinweis", locale: AppSettings.locale)
        content.subtitle = String(
            localized: "Gedrückt halten für Erledigt oder Verschieben",
            locale: AppSettings.locale
        )
        content.body = instruction
        content.sound = .default
        content.categoryIdentifier = reminderCategory
        content.threadIdentifier = recipeName
        content.userInfo = [
            recipeIDKey: recipeName,
            instructionKey: instruction,
            stepKey: "",
            scheduledDateKey: date.timeIntervalSince1970
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return UNNotificationRequest(
            identifier: "Recipe-\(UUID().uuidString)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    private static func fetchCurrentStep(
        metadata: ReminderMetadata,
        in context: NSManagedObjectContext
    ) -> NextStep? {
        let request = NextStep.fetchRequest()
        let lowerDate = metadata.scheduledDate.addingTimeInterval(-60)
        let upperDate = metadata.scheduledDate.addingTimeInterval(60)
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "instruction == %@ AND date >= %@ AND date <= %@",
            metadata.instruction,
            lowerDate as NSDate,
            upperDate as NSDate
        )
        return try? context.fetch(request).first
    }

    private static func metadata(from userInfo: [AnyHashable: Any]) -> ReminderMetadata? {
        guard let recipeID = userInfo[recipeIDKey] as? String,
              let instruction = userInfo[instructionKey] as? String,
              let scheduledDate = dateValue(userInfo[scheduledDateKey]) else {
            return nil
        }
        return ReminderMetadata(
            recipeID: recipeID,
            instruction: instruction,
            scheduledDate: scheduledDate
        )
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        if let value = value as? TimeInterval {
            return Date(timeIntervalSince1970: value)
        }
        if let value = value as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue)
        }
        return nil
    }

    private struct ReminderMetadata {
        let recipeID: String
        let instruction: String
        let scheduledDate: Date
    }

    private struct ScheduledNotificationMatch {
        let instruction: String
        let date: Date
    }
}

enum ScheduledStepShiftError: LocalizedError {
    case dateInPast
    case notificationNotFound

    var errorDescription: String? {
        switch self {
        case .dateInPast:
            return String(
                localized: "Der verschobene Zeitpunkt muss in der Zukunft liegen.",
                locale: AppSettings.locale
            )
        case .notificationNotFound:
            return String(
                localized: "Der zugehörige Reminder wurde nicht gefunden.",
                locale: AppSettings.locale
            )
        }
    }
}
