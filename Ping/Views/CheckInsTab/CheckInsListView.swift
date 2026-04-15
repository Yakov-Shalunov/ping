import SwiftUI
import SwiftData

struct CheckInsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.firstName) private var contacts: [Contact]
    @AppStorage("globalCheckInIntervalDays") private var globalDefault = 30

    @State private var showingLogSheet: Contact?
    @State private var showingSnoozeSheet: Contact?

    private var scheduledContacts: [Contact] {
        contacts.filter { $0.hasExplicitSchedule }
    }

    private var overdueContacts: [Contact] {
        scheduledContacts
            .filter { ($0.daysOverdue(globalDefault: globalDefault) ?? 0) > 0 }
            .sorted { ($0.daysOverdue(globalDefault: globalDefault) ?? 0) > ($1.daysOverdue(globalDefault: globalDefault) ?? 0) }
    }

    private var thisWeekContacts: [Contact] {
        scheduledContacts.filter {
            guard let days = $0.daysOverdue(globalDefault: globalDefault) else { return false }
            return days <= 0 && days >= -7
        }
        .sorted { ($0.nextDueDate(globalDefault: globalDefault) ?? .distantFuture) < ($1.nextDueDate(globalDefault: globalDefault) ?? .distantFuture) }
    }

    private var upcomingContacts: [Contact] {
        scheduledContacts.filter {
            guard let days = $0.daysOverdue(globalDefault: globalDefault) else { return false }
            return days < -7 && days >= -21
        }
        .sorted { ($0.nextDueDate(globalDefault: globalDefault) ?? .distantFuture) < ($1.nextDueDate(globalDefault: globalDefault) ?? .distantFuture) }
    }

    /// Contacts without an explicit schedule that are past the global default
    private var maybeReachOut: [Contact] {
        contacts.filter { contact in
            guard !contact.checkInDisabled else { return false }
            guard !contact.hasExplicitSchedule else { return false }
            let anchor = contact.lastCheckIn?.date ?? contact.createdAt
            let daysSince = Calendar.current.dateComponents([.day], from: anchor, to: Date()).day ?? 0
            return daysSince >= globalDefault
        }
        .sorted {
            let aDate = $0.lastCheckIn?.date ?? $0.createdAt
            let bDate = $1.lastCheckIn?.date ?? $1.createdAt
            return aDate < bDate
        }
    }

    /// Total overdue count for the tab badge
    var overdueCount: Int {
        overdueContacts.count
    }

    var body: some View {
        NavigationStack {
            List {
                if !overdueContacts.isEmpty {
                    checkInSection("Overdue", contacts: overdueContacts, tint: .red, showSnooze: true)
                }
                if !thisWeekContacts.isEmpty {
                    checkInSection("This Week", contacts: thisWeekContacts, tint: .orange, showSnooze: true)
                }
                if !upcomingContacts.isEmpty {
                    checkInSection("Next 2 Weeks", contacts: upcomingContacts, tint: .blue, showSnooze: true)
                }
                if !maybeReachOut.isEmpty {
                    Section {
                        ForEach(maybeReachOut) { contact in
                            CheckInRow(contact: contact, globalDefault: globalDefault, showScheduleHint: true)
                                .swipeActions(edge: .trailing) {
                                    Button("Done") { showingLogSheet = contact }
                                        .tint(.green)
                                }
                        }
                    } header: {
                        HStack {
                            Text("Maybe Reach Out")
                            Spacer()
                            Text("\(maybeReachOut.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if overdueContacts.isEmpty && thisWeekContacts.isEmpty && upcomingContacts.isEmpty && maybeReachOut.isEmpty {
                    ContentUnavailableView {
                        Label("All Caught Up", systemImage: "checkmark.circle")
                    } description: {
                        Text("No check-ins due. Set up schedules for your contacts.")
                    }
                }
            }
            .animation(.default, value: contacts.map(\.id))
            .navigationTitle("Check-ins")
            .navigationDestination(for: Contact.self) { contact in
                PersonDetailView(contact: contact)
            }
            .sheet(item: $showingLogSheet) { contact in
                LogCheckInSheet(contact: contact)
            }
            .sheet(item: $showingSnoozeSheet) { contact in
                SnoozeSheet(contact: contact)
            }
        }
    }

    private func checkInSection(_ title: String, contacts: [Contact], tint: Color, showSnooze: Bool) -> some View {
        Section {
            ForEach(contacts) { contact in
                CheckInRow(contact: contact, globalDefault: globalDefault, showScheduleHint: false)
                    .swipeActions(edge: .trailing) {
                        Button("Done") { showingLogSheet = contact }
                            .tint(.green)
                    }
                    .swipeActions(edge: .leading) {
                        if showSnooze {
                            Button("Snooze") { showingSnoozeSheet = contact }
                                .tint(.orange)
                        }
                    }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Text("\(contacts.count)")
                    .font(.caption)
                    .foregroundStyle(tint)
            }
        }
    }
}

// MARK: - Check-In Row

private struct CheckInRow: View {
    let contact: Contact
    let globalDefault: Int
    let showScheduleHint: Bool

    var body: some View {
        NavigationLink(value: contact) {
            HStack(spacing: 12) {
                ContactAvatar(contact: contact, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(contact.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                        if contact.isSnoozed {
                            Image(systemName: "moon.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }

                    if let lastCheckIn = contact.lastCheckIn {
                        let days = Calendar.current.dateComponents([.day], from: lastCheckIn.date, to: Date()).day ?? 0
                        Text("Last: \(lastCheckIn.type.label) \(days)d ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never contacted")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if showScheduleHint {
                        Text("No schedule set")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if let days = contact.daysOverdue(globalDefault: globalDefault), days > 0 {
                    Text("\(days)d late")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                } else if let due = contact.nextDueDate(globalDefault: globalDefault) {
                    Text(due, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Snooze Sheet

struct SnoozeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    @AppStorage("calendarSyncEnabled") private var calendarSyncEnabled = false
    @AppStorage("globalCheckInIntervalDays") private var globalDefault = 30
    let contact: Contact

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Snooze check-in for \(contact.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                Section("Snooze for...") {
                    Button { snooze(days: 1) } label: {
                        Label("1 day", systemImage: "clock")
                    }
                    Button { snooze(days: 3) } label: {
                        Label("3 days", systemImage: "clock")
                    }
                    Button { snooze(days: 7) } label: {
                        Label("1 week", systemImage: "clock")
                    }
                    Button { snooze(days: 14) } label: {
                        Label("2 weeks", systemImage: "clock")
                    }
                }
            }
            .navigationTitle("Snooze")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func snooze(days: Int) {
        contact.snoozedUntil = Calendar.current.date(byAdding: .day, value: days, to: Date())
        contact.updatedAt = Date()
        if calendarSyncEnabled {
            calendarSync.syncContact(contact, globalDefault: globalDefault)
        }
        dismiss()
    }
}
