import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    @AppStorage("globalCheckInIntervalDays") private var globalDefault = 30
    @AppStorage("calendarSyncEnabled") private var calendarSyncEnabled = false
    @AppStorage("contactWriteBackEnabled") private var contactWriteBackEnabled = false
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Query(filter: #Predicate<Contact> { !$0.isArchived }) private var activeContacts: [Contact]

    @State private var showingTidyUp = false
    @State private var showingTagManager = false
    @State private var showingImport = false
    @State private var showingSyncAllConfirmation = false
    @State private var syncAllInProgress = false
    @State private var syncAllResult: (synced: Int, failed: Int)?

    var body: some View {
        Form {
            Section("Check-in Defaults") {
                Picker("Default interval", selection: $globalDefault) {
                    Text("Every week").tag(7)
                    Text("Every 2 weeks").tag(14)
                    Text("Every 3 weeks").tag(21)
                    Text("Every month").tag(30)
                    Text("Every 2 months").tag(60)
                    Text("Every 3 months").tag(90)
                }
            }

            calendarSection
            contactsWriteBackSection

            Section("Data") {
                Button("Import from Contacts") {
                    showingImport = true
                }
                NavigationLink("Tidy Up Contacts") {
                    TidyUpView()
                }
                NavigationLink("Manage Tags") {
                    TagManagerView()
                }
                NavigationLink("Archived Contacts") {
                    ArchivedContactsView()
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showingImport) {
            ImportContactsView()
        }
    }

    // MARK: - Contacts Write-Back Section

    @ViewBuilder
    private var contactsWriteBackSection: some View {
        Section {
            Toggle("Sync Changes to Contacts", isOn: $contactWriteBackEnabled)
                .onChange(of: contactWriteBackEnabled) { _, enabled in
                    if enabled {
                        Task {
                            let writeBack = ContactWriteBack()
                            if !writeBack.isAuthorized {
                                let granted = await writeBack.requestAccess()
                                if !granted {
                                    contactWriteBackEnabled = false
                                }
                            }
                        }
                    }
                }
            if contactWriteBackEnabled {
                Button {
                    showingSyncAllConfirmation = true
                } label: {
                    HStack {
                        Text("Sync All Contacts Now")
                        Spacer()
                        if syncAllInProgress {
                            ProgressView()
                        }
                    }
                }
                .disabled(syncAllInProgress)

                if let result = syncAllResult {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(result.synced) synced\(result.failed > 0 ? ", \(result.failed) failed" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Contacts")
        } footer: {
            Text("When enabled, edits to imported contacts and new contacts created in Ping will be synced back to the Contacts app.")
        }
        .confirmationDialog(
            "Sync All Contacts",
            isPresented: $showingSyncAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sync \(activeContacts.count) Contacts") {
                performSyncAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will add any new phone numbers, emails, addresses, and social links from Ping to your system Contacts. Existing data in Contacts will not be modified or removed. Contacts created only in Ping will be added to the Contacts app.")
        }
    }

    private func performSyncAll() {
        syncAllInProgress = true
        syncAllResult = nil
        let writeBack = ContactWriteBack()
        var synced = 0
        var failed = 0
        for contact in activeContacts {
            do {
                let identifier = try writeBack.writeBack(contact)
                if contact.importedContactID == nil {
                    contact.importedContactID = identifier
                }
                synced += 1
            } catch {
                failed += 1
            }
        }
        try? modelContext.save()
        syncAllResult = (synced: synced, failed: failed)
        syncAllInProgress = false
    }

    // MARK: - Calendar Section

    @ViewBuilder
    private var calendarSection: some View {
        Section("Calendar") {
            Toggle("Sync to Calendar", isOn: $calendarSyncEnabled)
                .onChange(of: calendarSyncEnabled) { _, enabled in
                    if enabled {
                        Task { await enableCalendarSync() }
                    } else {
                        calendarSync.removeAllEvents()
                    }
                }

            if calendarSyncEnabled {
                if calendarSync.isAuthorized {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Syncing to \"Ping Check-ins\" calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Sync Now") {
                        calendarSync.syncAll(context: modelContext, globalDefault: globalDefault)
                    }

                    if let lastSync = calendarSync.lastSyncDate {
                        Text("Last synced: \(lastSync, format: .dateTime.hour().minute())")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Calendar access required")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Grant Access") {
                        Task { await enableCalendarSync() }
                    }
                }
            }
        }
    }

    private func enableCalendarSync() async {
        if !calendarSync.isAuthorized {
            let granted = await calendarSync.requestAccess()
            if !granted {
                calendarSyncEnabled = false
                return
            }
        }
        calendarSync.syncAll(context: modelContext, globalDefault: globalDefault)
    }
}

// MARK: - Tag Manager

struct TagManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var showingNewTag = false
    @State private var newTagName = ""

    var body: some View {
        List {
            ForEach(tags) { tag in
                HStack {
                    Circle()
                        .fill(tag.color)
                        .frame(width: 12, height: 12)
                    Text(tag.name)
                    Spacer()
                    Text("\((tag.contacts ?? []).count) contacts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete(perform: deleteTags)
        }
        .navigationTitle("Tags")
        .toolbar {
            Button { showingNewTag = true } label: {
                Image(systemName: "plus")
            }
        }
        .alert("New Tag", isPresented: $showingNewTag) {
            TextField("Tag name", text: $newTagName)
            Button("Add") {
                guard !newTagName.isEmpty else { return }
                modelContext.insert(Tag(name: newTagName))
                newTagName = ""
            }
            Button("Cancel", role: .cancel) { newTagName = "" }
        }
        .overlay {
            if tags.isEmpty {
                ContentUnavailableView {
                    Label("No Tags", systemImage: "tag")
                } description: {
                    Text("Tags help you organize and filter your contacts.")
                }
            }
        }
    }

    private func deleteTags(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tags[index])
        }
    }
}

// MARK: - Archived Contacts

struct ArchivedContactsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Contact> { $0.isArchived }, sort: \Contact.firstName) private var archivedContacts: [Contact]
    @AppStorage("globalCheckInIntervalDays") private var globalDefault = 30

    @State private var contactToDelete: Contact?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            ForEach(archivedContacts) { contact in
                HStack(spacing: 12) {
                    ContactAvatar(contact: contact, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                        if !contact.locationSummary.isEmpty {
                            Text(contact.locationSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .swipeActions(edge: .leading) {
                    Button {
                        contact.isArchived = false
                        contact.updatedAt = Date()
                    } label: {
                        Label("Unarchive", systemImage: "tray.and.arrow.up")
                    }
                    .tint(.green)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        contactToDelete = contact
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Archived")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Delete Contact", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let contact = contactToDelete {
                    modelContext.delete(contact)
                    contactToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { contactToDelete = nil }
        } message: {
            Text("Permanently delete \(contactToDelete?.displayName ?? "this contact")? This cannot be undone.")
        }
        .overlay {
            if archivedContacts.isEmpty {
                ContentUnavailableView {
                    Label("No Archived Contacts", systemImage: "archivebox")
                } description: {
                    Text("Contacts you archive will appear here.")
                }
            }
        }
    }
}
