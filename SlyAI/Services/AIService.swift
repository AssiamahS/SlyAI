import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: String
    let content: String
    let timestamp: Date
    var actions: [AIAction]

    init(role: String, content: String, actions: [AIAction] = []) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.actions = actions
    }
}

struct AIAction: Codable, Identifiable {
    var id: String { "\(type)-\(title ?? "")-\(delaySeconds ?? 0)" }
    let type: String
    let title: String?
    let startDate: String?
    let recurrence: String?
    let alertMinutes: Int?
    let notes: String?
    let dueDate: String?
    let time: String?
    let date: String?
    let repeats: String?
    let body: String?
    let delaySeconds: Int?

    enum CodingKeys: String, CodingKey {
        case type, title, recurrence, notes, time, date, repeats, body
        case startDate = "start_date"
        case alertMinutes = "alert_minutes"
        case dueDate = "due_date"
        case delaySeconds = "delay_seconds"
    }
}

struct ChatAPIResponse: Codable {
    let response: String
    let actions: [AIAction]
    let conversationId: String?

    enum CodingKeys: String, CodingKey {
        case response, actions
        case conversationId = "conversation_id"
    }
}

@MainActor
class AIService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: "slyai_server_url")
        }
    }

    private var conversationId: String?

    static let currentServerURL = "http://44.215.39.238:8080"

    init() {
        // Always use the current server URL (Elastic IP)
        // Override any stale cached value from before the IP change
        let saved = UserDefaults.standard.string(forKey: "slyai_server_url") ?? ""
        if saved.isEmpty || saved.contains("204.236.195.103") {
            self.serverURL = Self.currentServerURL
            UserDefaults.standard.set(Self.currentServerURL, forKey: "slyai_server_url")
        } else {
            self.serverURL = saved
        }
    }

    func sendMessage(_ text: String) async {
        let userMsg = ChatMessage(role: "user", content: text)
        messages.append(userMsg)
        isLoading = true

        defer { isLoading = false }

        guard let url = URL(string: "\(serverURL)/v1/chat") else {
            messages.append(ChatMessage(role: "assistant", content: "Invalid server URL."))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "message": text,
            "conversation_id": conversationId ?? "default"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                messages.append(ChatMessage(role: "assistant", content: "Server error. Check connection."))
                return
            }

            let decoded = try JSONDecoder().decode(ChatAPIResponse.self, from: data)
            conversationId = decoded.conversationId

            let assistantMsg = ChatMessage(
                role: "assistant",
                content: decoded.response,
                actions: decoded.actions
            )
            messages.append(assistantMsg)

            // Process actions
            for action in decoded.actions {
                await processAction(action)
            }

        } catch {
            messages.append(ChatMessage(role: "assistant", content: "Connection failed: \(error.localizedDescription)"))
        }
    }

    private func processAction(_ action: AIAction) async {
        switch action.type {
        case "calendar_event":
            await CalendarManager.shared.createEvent(from: action)
        case "reminder":
            await CalendarManager.shared.createReminder(from: action)
            // Also schedule a local notification so the user actually gets alerted
            NotificationManager.shared.scheduleReminderNotification(from: action)
        case "alarm":
            NotificationManager.shared.scheduleAlarm(from: action)
        case "notification":
            NotificationManager.shared.scheduleTimedNotification(from: action)
        default:
            break
        }
    }

    func clearHistory() {
        messages.removeAll()
        conversationId = nil
    }
}
