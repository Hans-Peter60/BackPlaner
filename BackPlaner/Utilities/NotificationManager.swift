//
//  NotificationManager.swift
//  Backplaner
//
//  Created by Hans-Peter Müller on 09.11.21.
//

import Foundation
import UserNotifications

struct DateCalculation {
    
    let formatter = DateFormatter()
    
    func calculateDateTime(dT: Date) -> String {
        
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: dT)
    }
}

class LocalNotificationManager: ObservableObject {
    
    @Published var notifications = [Notification]()
    
    func setNotification(_ id:String, _ instruction: String, _ step: String, _ startTime: Int, _ date: Date, _ scheduleNotificationsFlag: Bool) -> Date {
        
        var calcDate = date
        
        notifications = [Notification]()
 
        calcDate = Calendar.current.date(byAdding: .minute, value: startTime, to: calcDate)!
        
        let dateComponents = Calendar.current.dateComponents(in: .current, from: calcDate)
        let year = dateComponents.year
        let month = dateComponents.month
        let day = dateComponents.day
        let hour = dateComponents.hour
        let minute = dateComponents.minute

        notifications.append(Notification(id: "Recipe-\(id)-\(step)", title: instruction, datetime: DateComponents(calendar: Calendar.current, year: year, month: month, day: day, hour: hour, minute: minute)))
        
//        print("Recipe-", id, "-", step, instruction, "year: ", year, "month: ", month, "day: ", day, "hour: ", hour, "minute: ", minute)
        
        if scheduleNotificationsFlag {
            scheduleNotifications()
        }
        
        return calcDate
    }
  
    private func scheduleNotifications() {
        
        for notification in notifications {
            
            let content      = UNMutableNotificationContent()
            content.title    = notification.title
            content.sound    = .default
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: notification.datetime, repeats: false)
            
            let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request) { error in
                
                guard error == nil else { return }
                
                print("Notification scheduled! --- ID = \(notification.id)")
            }
        }
    }
    
    func listScheduledNotifications() {
        
        print("Anfrage der pending Notifications")
        UNUserNotificationCenter.current().getPendingNotificationRequests { notifications in
            
            for notification in notifications {
                print(notification)
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
    var title: String
    var datetime: DateComponents
}
