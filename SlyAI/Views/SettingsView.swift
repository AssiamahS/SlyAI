import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultPort") private var defaultPort = "22"
    @AppStorage("defaultUsername") private var defaultUsername = ""
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Defaults") {
                    HStack {
                        Text("Default Port")
                        Spacer()
                        TextField("22", text: $defaultPort)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Default Username")
                        Spacer()
                        TextField("root", text: $defaultUsername)
                            .textInputAutocapitalization(.never)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                }

                Section("Terminal") {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(terminalFontSize))pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $terminalFontSize, in: 8...24, step: 1)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("VPN Engine")
                        Spacer()
                        Text("blkstrvpn (WireGuard)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
