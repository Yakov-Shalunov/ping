import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.firstName) private var contacts: [Contact]
    @AppStorage("globalCheckInIntervalDays") private var globalDefault = 30
    @AppStorage("calendarSyncEnabled") private var calendarSyncEnabled = false
    @AppStorage("contactWriteBackEnabled") private var contactSyncEnabled = false

    private var overdueCount: Int {
        var count = 0
        for contact in contacts {
            if contact.hasExplicitSchedule,
               let days = contact.daysOverdue(globalDefault: globalDefault),
               days > 0 {
                count += 1
            }
        }
        return count
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
        .task {
            // Pull in changes from system Contacts on launch if sync enabled
            if contactSyncEnabled {
                let pullIn = ContactPullIn()
                if pullIn.isAuthorized {
                    await pullIn.pullIn(context: modelContext)
                }
            }
        }
    }
}
