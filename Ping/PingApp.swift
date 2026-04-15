import SwiftUI
import SwiftData

@main
struct PingApp: App {
    @StateObject private var calendarSync = CalendarSyncManager()
    @State private var saveErrorManager = SaveErrorManager()

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
                .environment(saveErrorManager)
                .overlay(alignment: .top) {
                    if let error = saveErrorManager.currentError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button { saveErrorManager.dismissError() } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.red, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut, value: saveErrorManager.currentError)
        }
        .modelContainer(modelContainer)
    }
}
