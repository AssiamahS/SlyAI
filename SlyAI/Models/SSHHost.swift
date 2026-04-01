import Foundation

struct SSHHost: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var hostname: String
    var port: Int
    var username: String
    var authMethod: AuthMethod

    enum AuthMethod: Codable, Hashable {
        case password(String)
        case privateKey(String) // path to key file
    }

    init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod = .password("")
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.authMethod = authMethod
    }

    static let example = SSHHost(
        name: "My VPS",
        hostname: "54.234.75.223",
        username: "ubuntu",
        authMethod: .privateKey("~/.ssh/id_rsa")
    )
}
