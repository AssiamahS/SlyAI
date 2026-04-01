import SwiftUI

@main
struct SlyAIApp: App {
    @StateObject private var connectionManager = ConnectionManager()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(connectionManager)
        }
    }
}
