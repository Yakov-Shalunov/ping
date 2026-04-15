import SwiftUI
import SwiftData
import Contacts

// MARK: - Phone Contact (lightweight wrapper for display)

struct PhoneContact: Identifiable, Hashable {
    let id: String // CNContact.identifier
    let firstName: String
    let lastName: String
    let nickname: String
    let phones: [(label: String?, value: String)]
    let emails: [(label: String?, value: String)]
    let addresses: [(label: String?, formatted: String)]
    let socialProfiles: [(platform: String, value: String)]
    let company: String
    let note: String
    let thumbnailData: Data?
    let imageData: Data?

    var displayName: String {
        let full = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        if !full.isEmpty { return full }
        if !nickname.isEmpty { return nickname }
        return phones.first?.value ?? emails.first?.value ?? "Unknown"
    }

    var subtitle: String {
        if let phone = phones.first { return phone.value }
        if let email = emails.first { return email.value }
        return ""
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PhoneContact, rhs: PhoneContact) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Contact Fetcher

enum ContactsAccess {
    case notDetermined
    case authorized
    case denied
    case restricted

    static func from(_ status: CNAuthorizationStatus) -> Self {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized, .limited: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }
}

@MainActor
final class ContactFetcher: ObservableObject {
    @Published var accessStatus: ContactsAccess = .notDetermined
    @Published var phoneContacts: [PhoneContact] = []
    @Published var isFetching = false

    private let store = CNContactStore()

    func checkAccess() {
        accessStatus = ContactsAccess.from(CNContactStore.authorizationStatus(for: .contacts))
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            accessStatus = granted ? .authorized : .denied
            if granted { await fetchContacts() }
        } catch {
            accessStatus = .denied
        }
    }

    func fetchContacts() async {
        isFetching = true

        // Note: CNContactNoteKey requires the com.apple.developer.contacts.notes
        // entitlement, which is not available for sideloaded apps. Requesting it
        // causes enumerateContacts to throw, so we skip it.
        nonisolated(unsafe) let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactNicknameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactPostalAddressesKey,
            CNContactSocialProfilesKey,
            CNContactOrganizationNameKey,
            CNContactThumbnailImageDataKey,
            CNContactImageDataKey,
            CNContactIdentifierKey,
        ] as [CNKeyDescriptor]

        // enumerateContacts is synchronous and blocking — run it off the main thread
        // CNContactStore and CNKeyDescriptor are not Sendable but are safe to use
        // from a background thread — suppress the warnings.
        nonisolated(unsafe) let store = self.store
        let results: [PhoneContact] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var contacts: [PhoneContact] = []
                let request = CNContactFetchRequest(keysToFetch: keysToFetch)
                request.sortOrder = .givenName

                do {
                    try store.enumerateContacts(with: request) { cnContact, _ in
                        let pc = PhoneContact(
                            id: cnContact.identifier,
                            firstName: cnContact.givenName,
                            lastName: cnContact.familyName,
                            nickname: cnContact.nickname,
                            phones: cnContact.phoneNumbers.map { (label: CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0.label ?? ""), value: $0.value.stringValue) },
                            emails: cnContact.emailAddresses.map { (label: CNLabeledValue<NSString>.localizedString(forLabel: $0.label ?? ""), value: $0.value as String) },
                            addresses: cnContact.postalAddresses.map { labeled in
                                let addr = labeled.value
                                let parts = [addr.street, addr.city, addr.state, addr.postalCode, addr.country].filter { !$0.isEmpty }
                                return (label: CNLabeledValue<CNPostalAddress>.localizedString(forLabel: labeled.label ?? ""), formatted: parts.joined(separator: ", "))
                            },
                            socialProfiles: cnContact.socialProfiles.map { (platform: $0.value.service, value: $0.value.urlString) },
                            company: cnContact.organizationName,
                            note: "",
                            thumbnailData: cnContact.thumbnailImageData,
                            imageData: cnContact.imageData
                        )
                        // Skip contacts with no useful info (just empty names)
                        if !pc.firstName.isEmpty || !pc.lastName.isEmpty || !pc.phones.isEmpty || !pc.emails.isEmpty {
                            contacts.append(pc)
                        }
                    }
                } catch {
                    // Silently fail — the list will just be empty
                }

                continuation.resume(returning: contacts)
            }
        }

        phoneContacts = results
        isFetching = false
    }
}

// MARK: - Phone Contact Row (extracted for SwiftUI diffing performance)

private enum ImportBadge: Equatable {
    case none, imported, archived
}

private struct PhoneContactRow: View, Equatable {
    let contact: PhoneContact
    let isSelected: Bool
    let badge: ImportBadge
    let onTap: () -> Void

    static func == (lhs: PhoneContactRow, rhs: PhoneContactRow) -> Bool {
        lhs.contact.id == rhs.contact.id && lhs.isSelected == rhs.isSelected && lhs.badge == rhs.badge
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)

                if let data = contact.thumbnailData, let img = PlatformImage(data: data) {
                    Image(platformImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Text(contact.displayName.prefix(1).uppercased())
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(contact.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if !contact.subtitle.isEmpty {
                        Text(contact.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                switch badge {
                case .imported:
                    Text("Imported")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                case .archived:
                    Text("Archived")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                case .none:
                    EmptyView()
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Import View

struct ImportContactsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.firstName) private var activeContacts: [Contact]
    @Query(filter: #Predicate<Contact> { $0.isArchived }, sort: \Contact.firstName) private var archivedContacts: [Contact]

    @StateObject private var fetcher = ContactFetcher()
    @State private var selectedIDs: Set<String> = []
    @State private var searchText = ""
    @State private var importPhase: ImportPhase = .selection
    @State private var importedCount = 0
    @State private var updatedCount = 0

    enum ImportPhase {
        case selection
        case importing
        case done
    }

    private var activeContactIDs: Set<String> {
        Set(activeContacts.compactMap(\.importedContactID))
    }

    private var archivedContactIDs: Set<String> {
        Set(archivedContacts.compactMap(\.importedContactID))
    }

    private var existingContactIDs: Set<String> {
        activeContactIDs.union(archivedContactIDs)
    }

    private var filteredContacts: [PhoneContact] {
        if searchText.isEmpty { return fetcher.phoneContacts }
        let query = searchText.lowercased()
        return fetcher.phoneContacts.filter {
            $0.displayName.lowercased().contains(query)
            || $0.phones.contains { $0.value.contains(query) }
            || $0.emails.contains { $0.value.lowercased().contains(query) }
        }
    }

    private var newContacts: [PhoneContact] {
        filteredContacts.filter { !existingContactIDs.contains($0.id) }
    }

    private var activeMatchedContacts: [PhoneContact] {
        filteredContacts.filter { activeContactIDs.contains($0.id) }
    }

    private var archivedMatchedContacts: [PhoneContact] {
        filteredContacts.filter { archivedContactIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch fetcher.accessStatus {
                case .notDetermined:
                    permissionRequestView
                case .authorized:
                    switch importPhase {
                    case .selection:
                        selectionView
                    case .importing:
                        importingView
                    case .done:
                        doneView
                    }
                case .denied, .restricted:
                    permissionDeniedView
                }
            }
            .navigationTitle("Import Contacts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if importPhase != .importing {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .onAppear {
                fetcher.checkAccess()
                if fetcher.accessStatus == .authorized {
                    Task { await fetcher.fetchContacts() }
                }
            }
        }
    }

    // MARK: - Permission Request

    private var permissionRequestView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
            Text("Import from Contacts")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Ping can import your contacts so you don't have to add them manually.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Button("Allow Access") {
                Task { await fetcher.requestAccess() }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Contacts Access Denied")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Open Settings and grant Ping access to your contacts to use this feature.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Selection

    private var selectionView: some View {
        VStack(spacing: 0) {
            if fetcher.isFetching {
                ProgressView("Loading contacts...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !newContacts.isEmpty {
                        Section {
                            ForEach(newContacts) { pc in
                                phoneContactRow(pc)
                            }
                        } header: {
                            HStack {
                                Text("New (\(newContacts.count))")
                                Spacer()
                                Button(allNewSelected ? "Deselect All" : "Select All") {
                                    toggleAllNew()
                                }
                                .font(.caption)
                            }
                        }
                    }

                    if !activeMatchedContacts.isEmpty {
                        Section {
                            ForEach(activeMatchedContacts) { pc in
                                phoneContactRow(pc)
                            }
                        } header: {
                            HStack {
                                Text("Already Imported (\(activeMatchedContacts.count))")
                                Spacer()
                                Button(allActiveSelected ? "Deselect All" : "Select All") {
                                    toggleAllActive()
                                }
                                .font(.caption)
                            }
                        }
                    }

                    if !archivedMatchedContacts.isEmpty {
                        Section {
                            ForEach(archivedMatchedContacts) { pc in
                                phoneContactRow(pc)
                            }
                        } header: {
                            HStack {
                                Text("Archived (\(archivedMatchedContacts.count))")
                                Spacer()
                                Button(allArchivedSelected ? "Deselect All" : "Select All") {
                                    toggleAllArchived()
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .animation(.default, value: fetcher.phoneContacts.map(\.id))
                .searchable(text: $searchText, prompt: "Search contacts...")

                // Bottom bar
                VStack(spacing: 8) {
                    Divider()
                    let newCount = selectedIDs.subtracting(existingContactIDs).count
                    let updateCount = selectedIDs.intersection(activeContactIDs).count
                    let unarchiveCount = selectedIDs.intersection(archivedContactIDs).count
                    if newCount > 0 || updateCount > 0 || unarchiveCount > 0 {
                        Text(importSummary(newCount: newCount, updateCount: updateCount, unarchiveCount: unarchiveCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        performImport()
                    } label: {
                        Text("Import \(selectedIDs.count) Contact\(selectedIDs.count == 1 ? "" : "s")")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIDs.isEmpty)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func phoneContactRow(_ pc: PhoneContact) -> some View {
        let badge: ImportBadge = archivedContactIDs.contains(pc.id) ? .archived
            : activeContactIDs.contains(pc.id) ? .imported : .none
        return PhoneContactRow(
            contact: pc,
            isSelected: selectedIDs.contains(pc.id),
            badge: badge
        ) {
            if selectedIDs.contains(pc.id) {
                selectedIDs.remove(pc.id)
            } else {
                selectedIDs.insert(pc.id)
            }
        }
    }

    private var allNewSelected: Bool {
        let newIDs = Set(newContacts.map(\.id))
        return !newIDs.isEmpty && newIDs.isSubset(of: selectedIDs)
    }

    private func toggleAllNew() {
        let newIDs = Set(newContacts.map(\.id))
        if allNewSelected {
            selectedIDs.subtract(newIDs)
        } else {
            selectedIDs.formUnion(newIDs)
        }
    }

    private var allActiveSelected: Bool {
        let ids = Set(activeMatchedContacts.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selectedIDs)
    }

    private func toggleAllActive() {
        let ids = Set(activeMatchedContacts.map(\.id))
        if allActiveSelected {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

    private var allArchivedSelected: Bool {
        let ids = Set(archivedMatchedContacts.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selectedIDs)
    }

    private func toggleAllArchived() {
        let ids = Set(archivedMatchedContacts.map(\.id))
        if allArchivedSelected {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

    private func importSummary(newCount: Int, updateCount: Int, unarchiveCount: Int) -> String {
        var parts: [String] = []
        if newCount > 0 { parts.append("\(newCount) new") }
        if updateCount > 0 { parts.append("\(updateCount) to update") }
        if unarchiveCount > 0 { parts.append("\(unarchiveCount) to unarchive") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Importing

    private var importingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Importing contacts...")
                .font(.headline)
            Spacer()
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("Import Complete")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 4) {
                if importedCount > 0 {
                    Text("\(importedCount) contact\(importedCount == 1 ? "" : "s") imported")
                }
                if updatedCount > 0 {
                    Text("\(updatedCount) contact\(updatedCount == 1 ? "" : "s") updated")
                }
            }
            .foregroundStyle(.secondary)

            Text("Many imported contacts may be missing locations and check-in schedules.")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    // MARK: - Import Logic

    private func performImport() {
        importPhase = .importing
        let selected = fetcher.phoneContacts.filter { selectedIDs.contains($0.id) }
        var newCount = 0
        var updateCount = 0

        let allExisting = activeContacts + archivedContacts
        for pc in selected {
            if let existing = allExisting.first(where: { $0.importedContactID == pc.id }) {
                updateExistingContact(existing, from: pc)
                updateCount += 1
            } else {
                createNewContact(from: pc)
                newCount += 1
            }
        }

        try? modelContext.save()

        importedCount = newCount
        updatedCount = updateCount
        importPhase = .done

        // Geocode imported addresses in the background
        Task {
            let geocoder = LocationGeocoder()
            await geocoder.geocodeMissingLocations(in: modelContext)
        }
    }

    private func createNewContact(from pc: PhoneContact) {
        let contact = Contact(firstName: pc.firstName, lastName: pc.lastName,
                              nickname: pc.nickname.isEmpty ? nil : pc.nickname)
        contact.importedContactID = pc.id
        contact.photoData = pc.imageData ?? pc.thumbnailData
        contact.notes = pc.note.isEmpty ? nil : pc.note
        if !pc.company.isEmpty {
            contact.affiliations = [pc.company]
        }

        // Phone numbers
        for phone in pc.phones {
            let method = ContactMethod(type: .phone, value: phone.value, label: phone.label)
            method.contact = contact
            contact.contactMethods?.append(method)
        }

        // Emails
        for email in pc.emails {
            let method = ContactMethod(type: .email, value: email.value, label: email.label)
            method.contact = contact
            contact.contactMethods?.append(method)
        }

        // Social profiles
        for social in pc.socialProfiles where !social.value.isEmpty {
            let method = ContactMethod(type: .social, value: social.value, platform: social.platform)
            method.contact = contact
            contact.contactMethods?.append(method)
        }

        // Addresses → locations (text only, no geocoding yet — user can fix in Tidy Up)
        for addr in pc.addresses where !addr.formatted.isEmpty {
            let loc = Location(label: addr.label ?? "Address", address: addr.formatted)
            loc.contact = contact
            contact.locations?.append(loc)
        }

        modelContext.insert(contact)
    }

    private func updateExistingContact(_ contact: Contact, from pc: PhoneContact) {
        // Unarchive if re-importing
        contact.isArchived = false

        // Update photo if we don't have one
        if contact.photoData == nil {
            contact.photoData = pc.imageData ?? pc.thumbnailData
        }

        // Add any new phone numbers we don't already have
        let existingPhones = Set((contact.contactMethods ?? []).filter { $0.type == .phone }.map(\.value))
        for phone in pc.phones where !existingPhones.contains(phone.value) {
            let method = ContactMethod(type: .phone, value: phone.value, label: phone.label)
            method.contact = contact
            contact.contactMethods?.append(method)
        }

        // Add any new emails we don't already have
        let existingEmails = Set((contact.contactMethods ?? []).filter { $0.type == .email }.map(\.value))
        for email in pc.emails where !existingEmails.contains(email.value) {
            let method = ContactMethod(type: .email, value: email.value, label: email.label)
            method.contact = contact
            contact.contactMethods?.append(method)
        }

        // Add new social profiles
        let existingSocials = Set((contact.contactMethods ?? []).filter { $0.type == .social }.map(\.value))
        for social in pc.socialProfiles where !social.value.isEmpty && !existingSocials.contains(social.value) {
            let method = ContactMethod(type: .social, value: social.value, platform: social.platform)
            method.contact = contact
            contact.contactMethods?.append(method)
        }

        // Add addresses as locations if we have none
        if (contact.locations ?? []).isEmpty {
            for addr in pc.addresses where !addr.formatted.isEmpty {
                let loc = Location(label: addr.label ?? "Address", address: addr.formatted)
                loc.contact = contact
                contact.locations?.append(loc)
            }
        }

        // Update affiliations if we don't have any
        if contact.affiliations.isEmpty && !pc.company.isEmpty {
            contact.affiliations = [pc.company]
        }

        // Update notes if we don't have any
        if contact.notes == nil && !pc.note.isEmpty {
            contact.notes = pc.note
        }

        contact.updatedAt = Date()
    }
}
