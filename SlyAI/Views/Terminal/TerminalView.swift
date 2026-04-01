import SwiftUI

struct TerminalView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    let host: SSHHost

    @State private var commandInput = ""
    @State private var outputLines: [TerminalLine] = []
    @State private var isConnecting = false
    @State private var isConnected = false
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Terminal output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(outputLines) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.color)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.black)
                .onChange(of: outputLines.count) {
                    if let last = outputLines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            // Input bar
            HStack(spacing: 8) {
                Text(isConnected ? "$" : ">")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.green)

                TextField("Enter command...", text: $commandInput)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($inputFocused)
                    .onSubmit {
                        sendCommand()
                    }

                Button {
                    sendCommand()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                }
                .disabled(commandInput.isEmpty || !isConnected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .navigationTitle(host.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if isConnected {
                        disconnect()
                    } else {
                        Task { await connect() }
                    }
                } label: {
                    Image(systemName: isConnected ? "wifi.slash" : "wifi")
                }
            }
        }
        .task {
            await connect()
        }
        .alert("Connection Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func connect() async {
        isConnecting = true
        appendLine("Connecting to \(host.username)@\(host.hostname):\(host.port)...", color: .yellow)

        do {
            _ = try await connectionManager.connect(to: host)
            isConnected = true
            appendLine("Connected!", color: .green)
            inputFocused = true
        } catch {
            errorMessage = error.localizedDescription
            appendLine("Error: \(error.localizedDescription)", color: .red)
        }

        isConnecting = false
    }

    private func disconnect() {
        connectionManager.disconnect(from: host)
        isConnected = false
        appendLine("Disconnected.", color: .yellow)
    }

    private func sendCommand() {
        let cmd = commandInput
        guard !cmd.isEmpty else { return }
        commandInput = ""

        appendLine("$ \(cmd)", color: .green)

        Task {
            do {
                if let session = connectionManager.activeSessions[host.id] {
                    let output = try await session.execute(cmd)
                    appendLine(output, color: .white)
                }
            } catch {
                appendLine("Error: \(error.localizedDescription)", color: .red)
            }
        }
    }

    private func appendLine(_ text: String, color: Color) {
        outputLines.append(TerminalLine(text: text, color: color))
    }
}

struct TerminalLine: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
}
