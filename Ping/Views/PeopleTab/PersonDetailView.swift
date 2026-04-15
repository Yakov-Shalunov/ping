import SwiftUI
import SwiftData
import MapKit

struct PersonDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("globalCheckInIntervalDays") private var globalDefault = 30

    let contact: Contact
    @State private var showingEdit = false
    @State private var showingLogCheckIn = false

    var body: some View {
        List {
            headerSection
            locationsSection
            checkInsSection
            contactInfoSection
            notesSection
        }
        .navigationTitle(contact.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            Button("Edit") { showingEdit = true }
        }
        .sheet(isPresented: $showingEdit) {
            AddEditContactView(contact: contact)
        }
        .sheet(isPresented: $showingLogCheckIn) {
            LogCheckInSheet(contact: contact)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    ContactAvatar(contact: contact, size: 80)
                    if !contact.affiliations.isEmpty {
                        Text(contact.affiliations.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(contact.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    if let nickname = contact.nickname, !nickname.isEmpty {
                        Text("\"\(nickname)\"")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !(contact.tags ?? []).isEmpty {
                        HStack(spacing: 6) {
                            ForEach(contact.tags ?? []) { tag in
                                Text(tag.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(tag.color.opacity(0.15))
                                    .foregroundStyle(tag.color)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Locations

    @ViewBuilder
    private var locationsSection: some View {
        if !(contact.locations ?? []).isEmpty {
            Section("Locations") {
                let coords = (contact.locations ?? []).map(\.coordinate)
                if let region = mapRegion(for: coords) {
                    Map(initialPosition: .region(region)) {
                        ForEach(contact.locations ?? []) { location in
                            Marker(location.label, coordinate: location.coordinate)
                        }
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                ForEach(contact.locations ?? []) { location in
                    Label {
                        VStack(alignment: .leading) {
                            Text(location.label)
                                .font(.body)
                            if let address = location.address, !address.isEmpty {
                                Text(address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: - Check-ins

    private var checkInsSection: some View {
        Section("Check-ins") {
            if let interval = contact.effectiveIntervalDays(globalDefault: globalDefault) {
                let weeks = interval / 7
                let suffix = contact.hasExplicitSchedule ? "" : " (default)"
                HStack {
                    Text("Every \(weeks > 0 ? "\(weeks) week\(weeks == 1 ? "" : "s")" : "\(interval) days")\(suffix)")
                        .font(.subheadline)
                    Spacer()
                    if let due = contact.nextDueDate(globalDefault: globalDefault) {
                        Text("Next: \(due, format: .dateTime.month().day())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if contact.checkInDisabled {
                Text("Check-ins disabled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if contact.isSnoozed, let until = contact.snoozedUntil {
                HStack {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(.orange)
                    Text("Snoozed until \(until, format: .dateTime.month().day())")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Clear") {
                        contact.snoozedUntil = nil
                    }
                    .font(.caption)
                }
            }

            ForEach(contact.sortedCheckIns.prefix(5)) { checkIn in
                CheckInHistoryRow(checkIn: checkIn)
            }

            if (contact.checkIns ?? []).count > 5 {
                NavigationLink {
                    FullCheckInHistoryView(contact: contact)
                } label: {
                    Text("View all \((contact.checkIns ?? []).count) check-ins")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Button { showingLogCheckIn = true } label: {
                Label("Log a Check-in", systemImage: "plus.circle")
            }
        }
    }

    // MARK: - Contact Info

    @ViewBuilder
    private var contactInfoSection: some View {
        let methods = contact.contactMethods ?? []
        if !methods.isEmpty {
            Section("Contact Info") {
                ForEach(methods) { method in
                    Label {
                        VStack(alignment: .leading) {
                            Text(method.value)
                                .font(.body)
                            if let label = method.label, !label.isEmpty {
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: method.type.systemImage)
                    }
                }
            }
        }
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesSection: some View {
        if let notes = contact.notes, !notes.isEmpty {
            Section("Notes") {
                Text(notes)
                    .font(.body)
            }
        }
    }

    // MARK: - Helpers

    private func mapRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.05),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.5, 0.05)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Log Check-In Sheet

struct LogCheckInSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    @AppStorage("calendarSyncEnabled") private var calendarSyncEnabled = false
    @AppStorage("globalCheckInIntervalDays") private var globalDefault = 30

    let contact: Contact
    @State private var type: CheckInType = .text
    @State private var date: Date = Date()
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("How did you connect?", selection: $type) {
                        ForEach(CheckInType.allCases) { t in
                            Label(t.label, systemImage: t.systemImage).tag(t)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.wheel)
                    #endif
                }

                Section("Date") {
                    DatePicker("When", selection: $date, in: ...Date(), displayedComponents: .date)
                }

                Section("Note") {
                    TextField("Optional note...", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Log Check-in")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        let checkIn = CheckIn(
            date: date,
            type: type,
            note: note.isEmpty ? nil : note
        )
        checkIn.contact = contact
        contact.checkIns?.append(checkIn)
        // Clear snooze when logging a check-in
        contact.snoozedUntil = nil
        contact.updatedAt = Date()

        // Sync calendar event for this contact
        if calendarSyncEnabled {
            calendarSync.syncContact(contact, globalDefault: globalDefault)
        }

        dismiss()
    }
}

// MARK: - Check-In History Row

struct CheckInHistoryRow: View {
    let checkIn: CheckIn

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: checkIn.type.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading) {
                Text("\(checkIn.date, format: .dateTime.month().day()) \u{00B7} \(checkIn.type.label)")
                    .font(.subheadline)
                if let note = checkIn.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - Full Check-In History

struct FullCheckInHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    let contact: Contact

    var body: some View {
        List {
            ForEach(contact.sortedCheckIns) { checkIn in
                CheckInHistoryRow(checkIn: checkIn)
            }
            .onDelete(perform: deleteCheckIns)
        }
        .navigationTitle("Check-in History")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func deleteCheckIns(at offsets: IndexSet) {
        let sorted = contact.sortedCheckIns
        for index in offsets {
            let checkIn = sorted[index]
            contact.checkIns?.removeAll { $0.id == checkIn.id }
            modelContext.delete(checkIn)
        }
    }
}
