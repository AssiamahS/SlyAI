import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Control Center: Open SlyAI

struct OpenSlyAIIntent: AppIntent {
    static let title: LocalizedStringResource = "Open SlyAI"
    static let description: IntentDescription = "Open the SlyAI app"
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

@available(iOS 18.0, *)
struct SlyAIControlWidget: ControlWidget {
    static let kind = "com.blkstr.slyai.control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenSlyAIIntent()) {
                Label("SlyAI", systemImage: "brain")
            }
        }
        .displayName("SlyAI")
        .description("Open SlyAI assistant")
    }
}

// MARK: - Control Center: Ask SlyAI

struct QuickRemindIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Remind"
    static let description: IntentDescription = "Set a quick SlyAI reminder"
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

@available(iOS 18.0, *)
struct SlyAIRemindControlWidget: ControlWidget {
    static let kind = "com.blkstr.slyai.remind-control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: QuickRemindIntent()) {
                Label("Remind", systemImage: "bell.badge")
            }
        }
        .displayName("SlyAI Remind")
        .description("Set a quick reminder with SlyAI")
    }
}

// MARK: - Widget Bundle

@available(iOS 18.0, *)
@main
struct SlyAIWidgetBundle: WidgetBundle {
    var body: some Widget {
        SlyAIControlWidget()
        SlyAIRemindControlWidget()
    }
}
