import SwiftUI
import SwiftData

struct PeopleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: [SortDescriptor(\Contact.firstName, comparator: .localized)]) private var contacts: [Contact]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @AppStorage("globalCheckInIntervalDays") private var globalDefault = 30

    @State private var searchText = ""
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var sortOrder = SortOrder.name
    @State private var showingAddContact = false
    @State private var showingSettings = false

    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case nextCheckIn = "Next Check-in"
        case lastContacted = "Last Contacted"
    }

    private var filteredContacts: [Contact] {
        var result = contacts

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { contact in
                contact.displayName.lowercased().contains(query)
                || (contact.nickname?.lowercased().contains(query) ?? false)
                || (contact.locations ?? []).contains { $0.label.lowercased().contains(query) }
            }
        }

        if !selectedTagIDs.isEmpty {
            result = result.filter { contact in
                let contactTagIDs = Set((contact.tags ?? []).map(\.id))
                return !selectedTagIDs.isDisjoint(with: contactTagIDs)
            }
        }

        switch sortOrder {
        case .name:
            break // already sorted by @Query
        case .nextCheckIn:
            result.sort { a, b in
                let aDate = a.nextDueDate(globalDefault: globalDefault)
                let bDate = b.nextDueDate(globalDefault: globalDefault)
                switch (aDate, bDate) {
                case let (a?, b?): return a < b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return false
                }
            }
        case .lastContacted:
            result.sort { a, b in
                let aDate = a.lastCheckIn?.date
                let bDate = b.lastCheckIn?.date
                switch (aDate, bDate) {
                case let (a?, b?): return a > b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return false
                }
            }
        }

        return result
    }

    var body: some View {
        NavigationStack {
            List {
                if !allTags.isEmpty {
                    TagFilterSection(allTags: allTags, selectedTagIDs: $selectedTagIDs)
                }

                ForEach(filteredContacts) { contact in
                    NavigationLink(value: contact) {
                        PersonRowView(contact: contact, globalDefault: globalDefault)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            archiveContact(contact)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(.orange)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search contacts...")
            .navigationTitle("People")
            .navigationDestination(for: Contact.self) { contact in
                PersonDetailView(contact: contact)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddContact = true } label: {
                        Image(systemName: "plus")
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                #else
                ToolbarItem {
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                #endif
                ToolbarItem(placement: .automatic) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingAddContact) {
                AddEditContactView()
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                }
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 500)
                #endif
            }
            .overlay {
                if contacts.isEmpty {
                    ContentUnavailableView {
                        Label("No Contacts", systemImage: "person.crop.circle.badge.plus")
                    } description: {
                        Text("Add someone to get started.")
                    } actions: {
                        Button("Add Contact") { showingAddContact = true }
                    }
                }
            }
        }
    }

    private func archiveContact(_ contact: Contact) {
        contact.isArchived = true
        contact.updatedAt = Date()
    }
}

// MARK: - Tag Filter Chips

private struct TagFilterSection: View {
    let allTags: [Tag]
    @Binding var selectedTagIDs: Set<UUID>

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allTags) { tag in
                        TagChip(
                            tag: tag,
                            isSelected: selectedTagIDs.contains(tag.id)
                        ) {
                            if selectedTagIDs.contains(tag.id) {
                                selectedTagIDs.remove(tag.id)
                            } else {
                                selectedTagIDs.insert(tag.id)
                            }
                        }
                    }
                    if !selectedTagIDs.isEmpty {
                        Button("Clear") {
                            selectedTagIDs.removeAll()
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
}

struct TagChip: View {
    let tag: Tag
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tag.name)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? tag.color.opacity(0.8) : tag.color.opacity(0.15))
                .foregroundStyle(isSelected ? .white : tag.color)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
