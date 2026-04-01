import SwiftUI

struct AIChatView: View {
    @StateObject private var aiService = AIService()
    @StateObject private var speechManager = SpeechManager()
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if aiService.messages.isEmpty { emptyState }

                        ForEach(aiService.messages) { msg in
                            MessageBubble(message: msg).id(msg.id)
                        }

                        if aiService.isLoading {
                            HStack {
                                ProgressView().tint(.green)
                                Text("Thinking...").font(.caption).foregroundStyle(.secondary)
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

            // Live transcript
            if speechManager.isListening {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(speechManager.transcript.isEmpty ? "Listening..." : speechManager.transcript)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }

            Divider()

            // Input bar
            HStack(spacing: 10) {
                Button {
                    if speechManager.isListening {
                        speechManager.stopListening()
                    } else {
                        Task {
                            if await speechManager.requestPermission() {
                                speechManager.startListening { text in sendMessage(text) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: speechManager.isListening ? "mic.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(speechManager.isListening ? .red : .green)
                }

                TextField("Ask SlyAI anything...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit { sendMessage(inputText) }

                Button(action: { sendMessage(inputText) }) {
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
                    Image(systemName: "trash").font(.caption)
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
        .onReceive(NotificationCenter.default.publisher(for: .slyAIStartListening)) { _ in
            Task {
                if await speechManager.requestPermission() {
                    speechManager.startListening { text in sendMessage(text) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "brain")
                .font(.system(size: 50))
                .foregroundStyle(.green.opacity(0.5))
            Text("SlyAI").font(.title2).fontWeight(.bold)
            Text("Your personal AI assistant").font(.subheadline).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                SuggestionChip(text: "Remind me to take out recycling every other Tuesday night") {
                    sendMessage("Remind me to take out recycling every other Tuesday night")
                }
                SuggestionChip(text: "Wake me up at 6am tomorrow") {
                    sendMessage("Wake me up at 6am tomorrow")
                }
                SuggestionChip(text: "Add a meeting tomorrow at 2pm") {
                    sendMessage("Add a meeting tomorrow at 2pm")
                }
            }
            .padding(.top, 8)

            HStack(spacing: 6) {
                Image(systemName: "mic.fill").font(.caption2)
                Text("Tap the mic to speak").font(.caption2)
            }
            .foregroundStyle(.secondary).padding(.top, 4)
        }
        .padding(.horizontal, 24)
    }

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        inputFocused = false
        Task { await aiService.sendMessage(trimmed) }
    }
}

struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "sparkles").font(.caption2)
                Text(text).font(.caption).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
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
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(isUser ? Color.green : Color(.systemGray5))
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                ForEach(message.actions) { action in ActionBadge(action: action) }
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
        case "calendar_event": "calendar.badge.plus"
        case "reminder": "bell.badge"
        case "alarm": "alarm"
        case "notification": "bell.badge.clock"
        default: "checkmark.circle"
        }
    }

    var label: String {
        switch action.type {
        case "calendar_event": "Added to Calendar"
        case "reminder": "Reminder Set"
        case "alarm": "Alarm Set"
        case "notification": "Notification Scheduled"
        default: "Done"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2)
            Text(label).font(.caption2).fontWeight(.medium)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.green.opacity(0.15))
        .foregroundStyle(.green)
        .clipShape(Capsule())
    }
}
