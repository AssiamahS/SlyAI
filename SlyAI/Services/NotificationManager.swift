import UserNotifications
import Foundation

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var permissionGranted = false
    @Published var lastStatus: String?

    private let serverURL: String = {
        UserDefaults.standard.string(forKey: "slyai_server_url") ?? AIService.currentServerURL
    }()

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                self.permissionGranted = granted
                self.reportStatus("permission", granted ? "granted" : "denied")
            }
        }
    }

    private func reportStatus(_ event: String, _ detail: String) {
        guard let url = URL(string: "\(serverURL)/v1/notify-status") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5
        let body: [String: String] = ["event": event, "detail": detail, "timestamp": ISO8601DateFormatter().string(from: Date())]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
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
                    self.reportStatus("notification_failed", error.localizedDescription)
                } else {
                    let minutes = delay / 60
                    self.lastStatus = "Reminder set for \(minutes) min from now"
                    self.reportStatus("notification_scheduled", "delay=\(delay)s title=\(action.title ?? "?")")
                }
            }
        }
    }

    func scheduleReminderNotification(from action: AIAction) {
        guard let dueDateStr = action.dueDate else { return }

        let localFormatter = DateFormatter()
        localFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        localFormatter.timeZone = .current

        guard let dueDate = localFormatter.date(from: dueDateStr) else { return }

        let delay = max(1, dueDate.timeIntervalSinceNow)

        let content = UNMutableNotificationContent()
        content.title = action.title ?? "SlyAI Reminder"
        content.body = action.notes ?? "Reminder due"
        content.sound = .defaultCritical
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(
            identifier: "slyai-reminder-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            Task { @MainActor in
                if let error {
                    self.lastStatus = "Reminder notification failed: \(error.localizedDescription)"
                    self.reportStatus("reminder_notif_failed", error.localizedDescription)
                } else {
                    let minutes = Int(delay / 60)
                    self.lastStatus = minutes > 0 ? "Reminder in \(minutes) min" : "Reminder in \(Int(delay))s"
                    self.reportStatus("reminder_notif_scheduled", "delay=\(Int(delay))s title=\(action.title ?? "?")")
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
                    self.reportStatus("alarm_failed", error.localizedDescription)
                } else {
                    self.lastStatus = "Alarm set for \(timeStr)"
                    self.reportStatus("alarm_scheduled", "time=\(timeStr) date=\(action.date ?? "?")")
                }
            }
        }
    }
}
