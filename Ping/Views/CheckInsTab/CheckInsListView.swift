import SwiftUI
import SwiftData

struct CheckInsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.firstName) private var contacts: [Contact]
    @AppStorage("globalCheckInIntervalDays") private var globalDefault = 30

    @State private var showingLogSheet: Contact?
    @State private var showingSnoozeSheet: Contact?

    /// Single-pass bucketing of all contacts into check-in sections.
    private var sections: CheckInSections {
        var overdue: [(contact: Contact, daysOverdue: Int)] = []
        var thisWeek: [(contact: Contact, dueDate: Date)] = []
        var upcoming: [(contact: Contact, dueDate: Date)] = []
        var maybeReachOut: [(contact: Contact, anchor: Date)] = []

        let now = Date()
        let calendar = Calendar.current

        for contact in contacts {
            if contact.checkInDisabled { continue }

            if contact.hasExplicitSchedule {
                guard let days = contact.daysOverdue(globalDefault: globalDefault) else { continue }
                if days > 0 {
                    overdue.append((contact, days))
                } else if days >= -7 {
                    let due = contact.nextDueDate(globalDefault: globalDefault) ?? .distantFuture
                    thisWeek.append((contact, due))
                } else if days >= -21 {
                    let due = contact.nextDueDate(globalDefault: globalDefault) ?? .distantFuture
                    upcoming.append((contact, due))
                }
            } else {
                let anchor = contact.lastCheckIn?.date ?? contact.createdAt
                let daysSince = calendar.dateComponents([.day], from: anchor, to: now).day ?? 0
                if daysSince >= globalDefault {
                    maybeReachOut.append((contact, anchor))
                }
            }
        }

        return CheckInSections(
            overdue: overdue.sorted { $0.daysOverdue > $1.daysOverdue }.map(\.contact),
            thisWeek: thisWeek.sorted { $0.dueDate < $1.dueDate }.map(\.contact),
            upcoming: upcoming.sorted { $0.dueDate < $1.dueDate }.map(\.contact),
            maybeReachOut: maybeReachOut.sorted { $0.anchor < $1.anchor }.map(\.contact)
        )
    }

    private struct CheckInSections {
        let overdue: [Contact]
        let thisWeek: [Contact]
        let upcoming: [Contact]
        let maybeReachOut: [Contact]
    }

    var body: some View {
        let s = sections
        NavigationStack {
            List {
                if !s.overdue.isEmpty {
                    checkInSection("Overdue", contacts: s.overdue, tint: .red, showSnooze: true)
                }
                if !s.thisWeek.isEmpty {
                    checkInSection("This Week", contacts: s.thisWeek, tint: .orange, showSnooze: true)
                }
                if !s.upcoming.isEmpty {
                    checkInSection("Next 2 Weeks", contacts: s.upcoming, tint: .blue, showSnooze: true)
                }
                if !s.maybeReachOut.isEmpty {
                    Section {
                        ForEach(s.maybeReachOut) { contact in
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
                            Text("\(s.maybeReachOut.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if s.overdue.isEmpty && s.thisWeek.isEmpty && s.upcoming.isEmpty && s.maybeReachOut.isEmpty {
                    ContentUnavailableView {
                        Label("All Caught Up", systemImage: "checkmark.circle")
                    } description: {
                        Text("No check-ins due. Set up schedules for your contacts.")
                    }
                }
            }
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
