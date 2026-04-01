import SwiftUI

struct VPNView: View {
    @State private var profiles: [VPNProfile] = []
    @State private var showAddProfile = false
    @State private var isConnected = false
    @State private var activeProfile: VPNProfile?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(isConnected ? "Connected" : "Disconnected")
                                .font(.headline)
                            if let profile = activeProfile {
                                Text(profile.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: $isConnected)
                            .labelsHidden()
                            .tint(.green)
                            .onChange(of: isConnected) { _, newValue in
                                if newValue {
                                    // TODO: Connect WireGuard tunnel
                                } else {
                                    activeProfile = nil
                                }
                            }
                    }
                } header: {
                    HStack {
                        Circle()
                            .fill(isConnected ? .green : .red)
                            .frame(width: 10, height: 10)
                        Text("Status")
                    }
                }

                Section("Profiles") {
                    if profiles.isEmpty {
                        ContentUnavailableView {
                            Label("No VPN Profiles", systemImage: "lock.shield")
                        } description: {
                            Text("Add a WireGuard profile to get started")
                        }
                    } else {
                        ForEach(profiles) { profile in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                        .font(.headline)
                                    Text(profile.endpoint)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if activeProfile?.id == profile.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                activeProfile = profile
                                isConnected = true
                            }
                        }
                        .onDelete { indexSet in
                            profiles.remove(atOffsets: indexSet)
                        }
                    }
                }

                Section("Info") {
                    Label("Protocol: WireGuard", systemImage: "network.badge.shield.half.filled")
                    Label("Powered by blkstrvpn", systemImage: "bolt.shield")
                }
            }
            .navigationTitle("VPN")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddProfile = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddProfile) {
                AddVPNProfileView { profile in
                    profiles.append(profile)
                }
            }
        }
    }
}

struct AddVPNProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (VPNProfile) -> Void

    @State private var name = ""
    @State private var endpoint = ""
    @State private var publicKey = ""
    @State private var privateKey = ""
    @State private var address = ""
    @State private var dns = "1.1.1.1"

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                    TextField("Endpoint (ip:port)", text: $endpoint)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }

                Section("Keys") {
                    TextField("Public Key", text: $publicKey)
                        .textInputAutocapitalization(.never)
                    SecureField("Private Key", text: $privateKey)
                }

                Section("Network") {
                    TextField("Address (e.g. 10.0.0.2/24)", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    TextField("DNS", text: $dns)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Add VPN Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let profile = VPNProfile(
                            name: name,
                            endpoint: endpoint,
                            publicKey: publicKey,
                            privateKey: privateKey,
                            address: address,
                            dns: dns
                        )
                        onSave(profile)
                        dismiss()
                    }
                    .disabled(name.isEmpty || endpoint.isEmpty)
                }
            }
        }
    }
}
