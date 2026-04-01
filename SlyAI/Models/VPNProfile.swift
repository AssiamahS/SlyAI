import Foundation

struct VPNProfile: Identifiable, Codable {
    var id: UUID
    var name: String
    var endpoint: String
    var publicKey: String
    var privateKey: String
    var address: String
    var dns: String
    var isActive: Bool

    init(
        id: UUID = UUID(),
        name: String,
        endpoint: String,
        publicKey: String = "",
        privateKey: String = "",
        address: String = "",
        dns: String = "1.1.1.1",
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.address = address
        self.dns = dns
        self.isActive = isActive
    }
}
