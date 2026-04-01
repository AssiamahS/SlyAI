import AppIntents
import Foundation

struct AskSlyAIIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask SlyAI"
    static let description: IntentDescription = "Send a message to your SlyAI assistant"
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Message")
    var message: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let serverURL = UserDefaults.standard.string(forKey: "slyai_server_url")
            ?? "http://44.215.39.238:8080"

        guard let url = URL(string: "\(serverURL)/v1/chat") else {
            return .result(dialog: "Server not configured.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = ["message": message, "conversation_id": "shortcut"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let apiResponse = try JSONDecoder().decode(ChatAPIResponse.self, from: data)

        for action in apiResponse.actions {
            switch action.type {
            case "calendar_event":
                await CalendarManager.shared.createEvent(from: action)
            case "reminder":
                await CalendarManager.shared.createReminder(from: action)
            case "alarm":
                NotificationManager.shared.scheduleAlarm(from: action)
            case "notification":
                NotificationManager.shared.scheduleTimedNotification(from: action)
            default:
                break
            }
        }

        return .result(dialog: "\(apiResponse.response)")
    }
}

struct VoiceSlyAIIntent: AppIntent {
    static let title: LocalizedStringResource = "Voice SlyAI"
    static let description: IntentDescription = "Open SlyAI in voice mode"
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .slyAIStartListening, object: nil)
        }
        return .result()
    }
}

extension Notification.Name {
    static let slyAIStartListening = Notification.Name("slyAIStartListening")
}

struct SlyAIShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskSlyAIIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Hey \(.applicationName)",
                "Tell \(.applicationName)",
                "\(.applicationName) remind me",
                "\(.applicationName) set alarm",
                "\(.applicationName) set reminder",
            ],
            shortTitle: "Ask SlyAI",
            systemImageName: "brain"
        )
        AppShortcut(
            intent: VoiceSlyAIIntent(),
            phrases: [
                "Voice \(.applicationName)",
                "Talk to \(.applicationName)",
                "\(.applicationName) listen",
            ],
            shortTitle: "Voice SlyAI",
            systemImageName: "mic.fill"
        )
    }
}
