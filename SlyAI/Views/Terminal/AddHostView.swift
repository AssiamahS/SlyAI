import SwiftUI

struct AddHostView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var hostname = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var password = ""
    @State private var useKeyAuth = false
    @State private var keyPath = "~/.ssh/id_rsa"

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.never)
                    TextField("Hostname / IP", text: $hostname)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                }

                Section("Authentication") {
                    Toggle("Use SSH Key", isOn: $useKeyAuth)

                    if useKeyAuth {
                        TextField("Key Path", text: $keyPath)
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
            }
            .navigationTitle("Add Host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let host = SSHHost(
                            name: name.isEmpty ? hostname : name,
                            hostname: hostname,
                            port: Int(port) ?? 22,
                            username: username,
                            authMethod: useKeyAuth
                                ? .privateKey(keyPath)
                                : .password(password)
                        )
                        connectionManager.saveHost(host)
                        dismiss()
                    }
                    .disabled(hostname.isEmpty || username.isEmpty)
                }
            }
        }
    }
}
