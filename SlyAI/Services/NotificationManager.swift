import UserNotifications
import Foundation

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var permissionGranted = false
    @Published var lastStatus: String?

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                self.permissionGranted = granted
            }
        }
    }

    func scheduleTimedNotification(from action: AIAction) {
        guard let delay = action.delaySeconds, delay > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = action.title ?? "SlyAI Reminder"
        content.body = action.body ?? "Time's up!"
        content.sound = .defaultCritical
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(delay), repeats: false)
        let request = UNNotificationRequest(
            identifier: "slyai-notification-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            Task { @MainActor in
                if let error {
                    self.lastStatus = "Notification failed: \(error.localizedDescription)"
                } else {
                    let minutes = delay / 60
                    self.lastStatus = "Reminder set for \(minutes) min from now"
                }
            }
        }
    }

    func scheduleAlarm(from action: AIAction) {
        let content = UNMutableNotificationContent()
        content.title = "SlyAI Alarm"
        content.body = action.title ?? "Time to wake up!"
        content.sound = .defaultCritical
        content.interruptionLevel = .timeSensitive

        guard let timeStr = action.time else { return }
        let timeParts = timeStr.split(separator: ":")
        guard timeParts.count == 2,
              let hour = Int(timeParts[0]),
              let minute = Int(timeParts[1]) else { return }

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        if let dateStr = action.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dateStr) {
                let cal = Calendar.current
                dateComponents.year = cal.component(.year, from: date)
                dateComponents.month = cal.component(.month, from: date)
                dateComponents.day = cal.component(.day, from: date)
            }
        }

        var repeats = false
        if let repeatType = action.repeats {
            switch repeatType {
            case "weekdays":
                for weekday in 2...6 {
                    var weekdayComponents = DateComponents()
                    weekdayComponents.hour = hour
                    weekdayComponents.minute = minute
                    weekdayComponents.weekday = weekday
                    let trigger = UNCalendarNotificationTrigger(dateMatching: weekdayComponents, repeats: true)
                    let request = UNNotificationRequest(
                        identifier: "slyai-alarm-\(weekday)-\(hour)\(minute)",
                        content: content,
                        trigger: trigger
                    )
                    UNUserNotificationCenter.current().add(request)
                }
                lastStatus = "Weekday alarm set for \(timeStr)"
                return

            case "daily":
                repeats = true
                dateComponents = DateComponents()
                dateComponents.hour = hour
                dateComponents.minute = minute

            case "once":
                repeats = false

            default:
                repeats = false
            }
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: repeats)
        let request = UNNotificationRequest(
            identifier: "slyai-alarm-\(hour)\(minute)-\(action.date ?? "once")",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            Task { @MainActor in
                if let error {
                    self.lastStatus = "Alarm failed: \(error.localizedDescription)"
                } else {
                    self.lastStatus = "Alarm set for \(timeStr)"
                }
            }
        }
    }
}
