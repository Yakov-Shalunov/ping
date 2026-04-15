import SwiftUI
import SwiftData

@main
struct PingApp: App {
    @StateObject private var calendarSync = CalendarSyncManager()

    let modelContainer: ModelContainer = {
        let schema = Schema([
            Contact.self,
            Location.self,
            Tag.self,
            ContactMethod.self,
            CheckIn.self,
            FieldStatus.self,
        ])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(calendarSync)
        }
        .modelContainer(modelContainer)
    }
}
