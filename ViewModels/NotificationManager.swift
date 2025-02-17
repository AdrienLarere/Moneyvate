import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    
    // Request authorization
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    // Helper: Given a goal, return an array of dates on which a completion is due.
    func datesForGoalNotifications(goal: Goal) -> [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: goal.startDate)
        let end = calendar.startOfDay(for: goal.endDate)
        var dates: [Date] = []
        var current = start
        while current <= end {
            switch goal.frequency {
            case .daily:
                dates.append(current)
            case .weekdays:
                if !calendar.isDateInWeekend(current) {
                    dates.append(current)
                }
            case .weekends:
                if calendar.isDateInWeekend(current) {
                    dates.append(current)
                }
            case .xDays:
                // For simplicity, schedule on every day.
                dates.append(current)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }
    
    // Schedule a notification for a specific goal on a given day.
    // The identifier is formed as "goalID_yyyy-MM-dd"
    func scheduleNotification(for goalID: String, on date: Date, at time: DateComponents, title: String, body: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        let identifier = "\(goalID)_\(dateString)"
        
        // Create a trigger by combining the date and the chosen time.
        var triggerDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        triggerDateComponents.hour = time.hour
        triggerDateComponents.minute = time.minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDateComponents, repeats: false)
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("Notification scheduled with id: \(identifier)")
            }
        }
    }
    
    // Cancel a notification for a given goal on a specific day.
    func cancelNotification(for goalID: String, on date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        let identifier = "\(goalID)_\(dateString)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        print("Canceled notification with id: \(identifier)")
    }
}
