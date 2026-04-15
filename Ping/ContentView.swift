import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.firstName) private var contacts: [Contact]
    @AppStorage("globalCheckInIntervalDays") private var globalDefault = 30
    @AppStorage("calendarSyncEnabled") private var calendarSyncEnabled = false

    private var overdueCount: Int {
        contacts.filter { contact in
            contact.hasExplicitSchedule
            && (contact.daysOverdue(globalDefault: globalDefault) ?? 0) > 0
        }.count
    }

    var body: some View {
        TabView {
            PeopleListView()
                .tabItem {
                    Label("People", systemImage: "person.2.fill")
                }

            CheckInsListView()
                .tabItem {
                    Label("Check-ins", systemImage: "bell.fill")
                }
                .badge(overdueCount)

            ContactMapView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
        }
        .task {
            let geocoder = LocationGeocoder()
            await geocoder.geocodeMissingLocations(in: modelContext)
        }
        .task {
            // Sync calendar on launch if enabled
            if calendarSyncEnabled && calendarSync.isAuthorized {
                calendarSync.syncAll(context: modelContext, globalDefault: globalDefault)
            }
        }
    }
}
