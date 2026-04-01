import SwiftUI

struct TerminalListView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showAddHost = false

    var body: some View {
        NavigationStack {
            List {
                if !connectionManager.activeSessions.isEmpty {
                    Section("Active Sessions") {
                        ForEach(connectionManager.savedHosts.filter {
                            connectionManager.activeSessions[$0.id] != nil
                        }) { host in
                            NavigationLink {
                                TerminalView(host: host)
                            } label: {
                                HostRow(host: host, isConnected: true)
                            }
                        }
                    }
                }

                Section("Saved Hosts") {
                    ForEach(connectionManager.savedHosts) { host in
                        NavigationLink {
                            TerminalView(host: host)
                        } label: {
                            HostRow(
                                host: host,
                                isConnected: connectionManager.activeSessions[host.id] != nil
                            )
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            connectionManager.deleteHost(connectionManager.savedHosts[index])
                        }
                    }
                }
            }
            .navigationTitle("Terminal")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddHost = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddHost) {
                AddHostView()
            }
        }
    }
}

struct HostRow: View {
    let host: SSHHost
    let isConnected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(host.name)
                    .font(.headline)
                Text("\(host.username)@\(host.hostname):\(host.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isConnected {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
        }
    }
}
