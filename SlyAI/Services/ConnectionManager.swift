import Foundation
import Combine

@MainActor
class ConnectionManager: ObservableObject {
    @Published var savedHosts: [SSHHost] = []
    @Published var activeSessions: [UUID: SSHSession] = [:]

    private let hostsKey = "saved_hosts"

    init() {
        loadHosts()
    }

    func saveHost(_ host: SSHHost) {
        if let index = savedHosts.firstIndex(where: { $0.id == host.id }) {
            savedHosts[index] = host
        } else {
            savedHosts.append(host)
        }
        persistHosts()
    }

    func deleteHost(_ host: SSHHost) {
        savedHosts.removeAll { $0.id == host.id }
        persistHosts()
    }

    func connect(to host: SSHHost) async throws -> SSHSession {
        let session = SSHSession(host: host)
        try await session.connect()
        activeSessions[host.id] = session
        return session
    }

    func disconnect(from host: SSHHost) {
        activeSessions[host.id]?.disconnect()
        activeSessions.removeValue(forKey: host.id)
    }

    private func loadHosts() {
        guard let data = UserDefaults.standard.data(forKey: hostsKey),
              let hosts = try? JSONDecoder().decode([SSHHost].self, from: data) else {
            return
        }
        savedHosts = hosts
    }

    private func persistHosts() {
        guard let data = try? JSONEncoder().encode(savedHosts) else { return }
        UserDefaults.standard.set(data, forKey: hostsKey)
    }
}
