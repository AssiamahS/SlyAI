import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TerminalListView()
                .tabItem {
                    Label("Terminal", systemImage: "terminal")
                }
                .tag(0)

            VPNView()
                .tabItem {
                    Label("VPN", systemImage: "lock.shield")
                }
                .tag(1)

            AIView()
                .tabItem {
                    Label("AI", systemImage: "brain")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .tint(.green)
    }
}
