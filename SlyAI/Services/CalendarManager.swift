import EventKit
import Foundation

@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    private let eventStore = EKEventStore()
    @Published var calendarAccessGranted = false
    @Published var reminderAccessGranted = false
    @Published var lastStatus: String?

    func requestCalendarAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            calendarAccessGranted = granted
        } catch {
            calendarAccessGranted = false
        }
    }

    func requestReminderAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            reminderAccessGranted = granted
        } catch {
            reminderAccessGranted = false
        }
    }

    func createEvent(from action: AIAction) async {
        if !calendarAccessGranted {
            await requestCalendarAccess()
        }

        guard calendarAccessGranted else {
            lastStatus = "Calendar access denied"
            return
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = action.title ?? "SlyAI Event"
        event.calendar = eventStore.defaultCalendarForNewEvents

        // Parse start date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try multiple formats
        let dateStr = action.startDate ?? ""
        var startDate: Date?

        // Try ISO8601 with timezone
        startDate = formatter.date(from: dateStr)

        // Try without timezone (local time)
        if startDate == nil {
            let localFormatter = DateFormatter()
            localFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            localFormatter.timeZone = .current
            startDate = localFormatter.date(from: dateStr)
        }

        event.startDate = startDate ?? Date()
        event.endDate = event.startDate.addingTimeInterval(3600) // 1 hour default

        if let notes = action.notes {
            event.notes = notes
        }

        // Set alert
        if let alertMin = action.alertMinutes {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-alertMin * 60)))
        }

        // Set recurrence rule
        if let rruleString = action.recurrence {
            if let rule = parseRRule(rruleString) {
                event.addRecurrenceRule(rule)
            }
        }

        do {
            try eventStore.save(event, span: .futureEvents)
            lastStatus = "Added '\(event.title ?? "event")' to calendar"
        } catch {
            lastStatus = "Failed to save event: \(error.localizedDescription)"
        }
    }

    func createReminder(from action: AIAction) async {
        if !reminderAccessGranted {
            await requestReminderAccess()
        }

        guard reminderAccessGranted else {
            lastStatus = "Reminder access denied"
            return
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = action.title ?? "SlyAI Reminder"
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        if let notes = action.notes {
            reminder.notes = notes
        }

        // Parse due date
        if let dueDateStr = action.dueDate {
            let localFormatter = DateFormatter()
            localFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            localFormatter.timeZone = .current
            if let dueDate = localFormatter.date(from: dueDateStr) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: dueDate
                )
                reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
            }
        }

        do {
            try eventStore.save(reminder, commit: true)
            lastStatus = "Reminder set: '\(reminder.title ?? "reminder")'"
        } catch {
            lastStatus = "Failed to save reminder: \(error.localizedDescription)"
        }
    }

    private func parseRRule(_ rrule: String) -> EKRecurrenceRule? {
        // Parse iCalendar RRULE format
        var freq: EKRecurrenceFrequency = .weekly
        var interval = 1
        var daysOfWeek: [EKRecurrenceDayOfWeek]?

        let parts = rrule.split(separator: ";")
        for part in parts {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = String(kv[0])
            let value = String(kv[1])

            switch key {
            case "FREQ":
                switch value {
                case "DAILY": freq = .daily
                case "WEEKLY": freq = .weekly
                case "MONTHLY": freq = .monthly
                case "YEARLY": freq = .yearly
                default: break
                }
            case "INTERVAL":
                interval = Int(value) ?? 1
            case "BYDAY":
                daysOfWeek = value.split(separator: ",").compactMap { dayStr in
                    let day = String(dayStr).trimmingCharacters(in: .whitespaces)
                    switch day {
                    case "MO": return EKRecurrenceDayOfWeek(.monday)
                    case "TU": return EKRecurrenceDayOfWeek(.tuesday)
                    case "WE": return EKRecurrenceDayOfWeek(.wednesday)
                    case "TH": return EKRecurrenceDayOfWeek(.thursday)
                    case "FR": return EKRecurrenceDayOfWeek(.friday)
                    case "SA": return EKRecurrenceDayOfWeek(.saturday)
                    case "SU": return EKRecurrenceDayOfWeek(.sunday)
                    default: return nil
                    }
                }
            default:
                break
            }
        }

        return EKRecurrenceRule(
            recurrenceWith: freq,
            interval: interval,
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
    }
}
