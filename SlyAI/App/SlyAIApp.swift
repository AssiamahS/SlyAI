import SwiftUI
import CoreSpotlight
import UniformTypeIdentifiers

@main
struct SlyAIApp: App {
    @StateObject private var connectionManager = ConnectionManager()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(connectionManager)
                .onAppear { donateToSpotlight() }
        }
    }

    private func donateToSpotlight() {
        let attributes = CSSearchableItemAttributeSet(contentType: .application)
        attributes.title = "SlyAI"
        attributes.contentDescription = "Personal AI Assistant — reminders, alarms, calendar, chat"
        attributes.keywords = ["SlyAI", "Sly", "AI", "assistant", "reminder", "alarm", "calendar"]

        let item = CSSearchableItem(
            uniqueIdentifier: "com.blkstr.slyai.main",
            domainIdentifier: "com.blkstr.slyai",
            attributeSet: attributes
        )
        item.expirationDate = .distantFuture

        CSSearchableIndex.default().indexSearchableItems([item])
    }
}
