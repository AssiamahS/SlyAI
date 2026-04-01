import SwiftUI

struct AIChatView: View {
    @StateObject private var aiService = AIService()
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if aiService.messages.isEmpty {
                            emptyState
                        }

                        ForEach(aiService.messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }

                        if aiService.isLoading {
                            HStack {
                                ProgressView()
                                    .tint(.green)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("loading")
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: aiService.messages.count) {
                    withAnimation {
                        if let last = aiService.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 12) {
                TextField("Ask SlyAI anything...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit { sendMessage() }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(inputText.isEmpty ? .gray : .green)
                }
                .disabled(inputText.isEmpty || aiService.isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("SlyAI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { aiService.clearHistory() }) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
            }
        }
        .onAppear {
            Task {
                await CalendarManager.shared.requestCalendarAccess()
                await CalendarManager.shared.requestReminderAccess()
                NotificationManager.shared.requestPermission()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "brain")
                .font(.system(size: 50))
                .foregroundStyle(.green.opacity(0.5))
            Text("SlyAI")
                .font(.title2)
                .fontWeight(.bold)
            Text("Your personal AI assistant")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                SuggestionChip(text: "Remind me to take out recycling every other Tuesday night") {
                    inputText = "Remind me to take out recycling every other Tuesday night"
                    sendMessage()
                }
                SuggestionChip(text: "Wake me up at 6am tomorrow") {
                    inputText = "Wake me up at 6am tomorrow"
                    sendMessage()
                }
                SuggestionChip(text: "Add a meeting tomorrow at 2pm") {
                    inputText = "Add a meeting tomorrow at 2pm"
                    sendMessage()
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        Task {
            await aiService.sendMessage(text)
        }
    }
}

struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text(text)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.green.opacity(0.1))
            .foregroundStyle(.green)
            .clipShape(Capsule())
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.green : Color(.systemGray5))
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                // Show action confirmations
                ForEach(message.actions) { action in
                    ActionBadge(action: action)
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
    }
}

struct ActionBadge: View {
    let action: AIAction

    var icon: String {
        switch action.type {
        case "calendar_event": return "calendar.badge.plus"
        case "reminder": return "bell.badge"
        case "alarm": return "alarm"
        case "notification": return "bell.badge.clock"
        default: return "checkmark.circle"
        }
    }

    var label: String {
        switch action.type {
        case "calendar_event": return "Added to Calendar"
        case "reminder": return "Reminder Set"
        case "alarm": return "Alarm Set"
        case "notification": return "Notification Scheduled"
        default: return "Done"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.green.opacity(0.15))
        .foregroundStyle(.green)
        .clipShape(Capsule())
    }
}
