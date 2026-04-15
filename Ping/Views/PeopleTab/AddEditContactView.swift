import SwiftUI
import SwiftData
import MapKit

struct AddEditContactView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var allTags: [Tag]

    let contact: Contact?

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var nickname = ""
    @State private var notes = ""
    @State private var affiliations: [String] = []
    @FocusState private var focusedAffiliationIndex: Int?
    @State private var checkInWeeks: Int? = nil
    @State private var checkInDisabled = false
    @State private var locations: [LocationDraft] = []
    @State private var phones: [MethodDraft] = []
    @State private var emails: [MethodDraft] = []
    @State private var socials: [SocialDraft] = []
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var showingNewTag = false
    @State private var newTagName = ""
    @State private var showingDeleteConfirmation = false
    @AppStorage("contactWriteBackEnabled") private var contactWriteBackEnabled = false

    init(contact: Contact? = nil) {
        self.contact = contact
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                affiliationsSection
                scheduleSection
                tagsSection
                locationsSection
                phonesSection
                emailsSection
                socialsSection
                notesSection
                if contact != nil {
                    dangerSection
                }
            }
            .navigationTitle(contact == nil ? "Add Contact" : "Edit Contact")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(firstName.isEmpty && lastName.isEmpty)
                }
            }
            .onAppear { loadFromContact() }
            .alert("Delete Contact", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) { deleteContact() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete this contact and all their data. This cannot be undone.")
            }
            .alert("New Tag", isPresented: $showingNewTag) {
                TextField("Tag name", text: $newTagName)
                Button("Add") { addNewTag() }
                Button("Cancel", role: .cancel) { newTagName = "" }
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Name") {
            TextField("First name", text: $firstName)
            TextField("Last name", text: $lastName)
            TextField("Nickname", text: $nickname)
        }
    }

    private var affiliationsSection: some View {
        Section("Affiliations") {
            ForEach(affiliations.indices, id: \.self) { index in
                TextField("Affiliation", text: $affiliations[index])
                    .focused($focusedAffiliationIndex, equals: index)
            }
            .onDelete { affiliations.remove(atOffsets: $0) }
            .onMove { affiliations.move(fromOffsets: $0, toOffset: $1) }

            TextField("Add affiliation (e.g. company)", text: .constant(""))
                .focused($focusedAffiliationIndex, equals: -1)
                .onChange(of: focusedAffiliationIndex) { _, newValue in
                    if newValue == -1 {
                        let newIndex = affiliations.count
                        affiliations.append("")
                        focusedAffiliationIndex = newIndex
                    }
                }
        }
    }

    private var scheduleSection: some View {
        Section("Check-in Schedule") {
            Toggle("Disable check-ins", isOn: $checkInDisabled)
            if !checkInDisabled {
                Picker("Frequency", selection: $checkInWeeks) {
                    Text("Use default").tag(nil as Int?)
                    Text("Every week").tag(1 as Int?)
                    Text("Every 2 weeks").tag(2 as Int?)
                    Text("Every 3 weeks").tag(3 as Int?)
                    Text("Every month").tag(4 as Int?)
                    Text("Every 2 months").tag(8 as Int?)
                    Text("Every 3 months").tag(13 as Int?)
                    Text("Every 6 months").tag(26 as Int?)
                }
            }
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            if !allTags.isEmpty {
                FlowLayout(spacing: 8) {
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
                }
                .padding(.vertical, 4)
            }
            Button { showingNewTag = true } label: {
                Label("New Tag", systemImage: "plus")
            }
        }
    }

    private var locationsSection: some View {
        Section("Locations") {
            ForEach($locations) { $loc in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Label (e.g. Home in NYC)", text: $loc.label)
                    LocationSearchField(draft: $loc)
                    if loc.latitude != 0 || loc.longitude != 0 {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        ))) {
                            Marker(loc.label.isEmpty ? "Location" : loc.label,
                                   coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude))
                        }
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete { locations.remove(atOffsets: $0) }

            Button { locations.append(LocationDraft()) } label: {
                Label("Add Location", systemImage: "mappin.circle")
            }
        }
    }

    private var phonesSection: some View {
        Section("Phone Numbers") {
            ForEach($phones) { $phone in
                HStack {
                    TextField("Label", text: $phone.label)
                        .frame(width: 80)
                    TextField("Phone number", text: $phone.value)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                }
            }
            .onDelete { phones.remove(atOffsets: $0) }

            Button { phones.append(MethodDraft(label: "Personal")) } label: {
                Label("Add Phone", systemImage: "phone")
            }
        }
    }

    private var emailsSection: some View {
        Section("Email Addresses") {
            ForEach($emails) { $email in
                HStack {
                    TextField("Label", text: $email.label)
                        .frame(width: 80)
                    TextField("Email address", text: $email.value)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                }
            }
            .onDelete { emails.remove(atOffsets: $0) }

            Button { emails.append(MethodDraft(label: "Personal")) } label: {
                Label("Add Email", systemImage: "envelope")
            }
        }
    }

    private var socialsSection: some View {
        Section("Social Links") {
            ForEach($socials) { $social in
                VStack {
                    TextField("Platform (e.g. LinkedIn)", text: $social.platform)
                    TextField("URL or username", text: $social.value)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
            }
            .onDelete { socials.remove(atOffsets: $0) }

            Button { socials.append(SocialDraft()) } label: {
                Label("Add Social Link", systemImage: "link")
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Notes about this person...", text: $notes, axis: .vertical)
                .lineLimit(3...10)
        }
    }

    private var dangerSection: some View {
        Section {
            if contact?.isArchived == true {
                Button {
                    contact?.isArchived = false
                    contact?.updatedAt = Date()
                    dismiss()
                } label: {
                    Label("Unarchive Contact", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button(role: .destructive) {
                    contact?.isArchived = true
                    contact?.updatedAt = Date()
                    dismiss()
                } label: {
                    Label("Archive Contact", systemImage: "archivebox")
                        .foregroundStyle(.orange)
                }
            }
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Contact", systemImage: "trash")
            }
        }
    }

    // MARK: - Load / Save

    private func loadFromContact() {
        guard let contact else { return }
        firstName = contact.firstName
        lastName = contact.lastName
        nickname = contact.nickname ?? ""
        notes = contact.notes ?? ""
        checkInWeeks = contact.checkInIntervalDays.map { $0 / 7 }
        checkInDisabled = contact.checkInDisabled
        affiliations = contact.affiliations
        selectedTagIDs = Set((contact.tags ?? []).map(\.id))

        locations = (contact.locations ?? []).map {
            LocationDraft(id: $0.id, label: $0.label, address: $0.address ?? "", latitude: $0.latitude, longitude: $0.longitude)
        }
        phones = (contact.contactMethods ?? []).filter { $0.type == .phone }.map {
            MethodDraft(id: $0.id, label: $0.label ?? "", value: $0.value)
        }
        emails = (contact.contactMethods ?? []).filter { $0.type == .email }.map {
            MethodDraft(id: $0.id, label: $0.label ?? "", value: $0.value)
        }
        socials = (contact.contactMethods ?? []).filter { $0.type == .social }.map {
            SocialDraft(id: $0.id, platform: $0.platform ?? "", value: $0.value)
        }
    }

    private func save() {
        let target: Contact
        if let existing = contact {
            target = existing
        } else {
            target = Contact()
            modelContext.insert(target)
        }

        target.firstName = firstName
        target.lastName = lastName
        target.nickname = nickname.isEmpty ? nil : nickname
        target.notes = notes.isEmpty ? nil : notes
        target.checkInIntervalDays = checkInWeeks.map { $0 * 7 }
        target.checkInDisabled = checkInDisabled
        target.affiliations = affiliations.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        target.updatedAt = Date()

        // Sync locations
        let existingLocations = target.locations ?? []
        for loc in existingLocations {
            modelContext.delete(loc)
        }
        target.locations = []
        for draft in locations where !draft.label.isEmpty {
            let loc = Location(label: draft.label, address: draft.address.isEmpty ? nil : draft.address,
                               latitude: draft.latitude, longitude: draft.longitude)
            loc.contact = target
            target.locations?.append(loc)
        }

        // Sync contact methods
        let existingMethods = target.contactMethods ?? []
        for m in existingMethods {
            modelContext.delete(m)
        }
        target.contactMethods = []
        for draft in phones where !draft.value.isEmpty {
            let m = ContactMethod(type: .phone, value: draft.value, label: draft.label.isEmpty ? nil : draft.label)
            m.contact = target
            target.contactMethods?.append(m)
        }
        for draft in emails where !draft.value.isEmpty {
            let m = ContactMethod(type: .email, value: draft.value, label: draft.label.isEmpty ? nil : draft.label)
            m.contact = target
            target.contactMethods?.append(m)
        }
        for draft in socials where !draft.value.isEmpty {
            let m = ContactMethod(type: .social, value: draft.value, platform: draft.platform.isEmpty ? nil : draft.platform)
            m.contact = target
            target.contactMethods?.append(m)
        }

        // Sync tags
        target.tags = allTags.filter { selectedTagIDs.contains($0.id) }

        // Write back to system Contacts app if enabled
        if contactWriteBackEnabled {
            let writeBack = ContactWriteBack()
            if writeBack.isAuthorized {
                do {
                    let identifier = try writeBack.writeBack(target)
                    if target.importedContactID == nil {
                        target.importedContactID = identifier
                    }
                } catch {
                    // Silently fail — the Ping save still succeeds
                }
            }
        }

        dismiss()
    }

    private func addNewTag() {
        guard !newTagName.isEmpty else { return }
        let tag = Tag(name: newTagName)
        modelContext.insert(tag)
        selectedTagIDs.insert(tag.id)
        newTagName = ""
    }

    private func deleteContact() {
        guard let contact else { return }
        modelContext.delete(contact)
        dismiss()
    }
}

// MARK: - Draft Models (transient, for the form)

struct LocationDraft: Identifiable {
    var id = UUID()
    var label = ""
    var address = ""
    var latitude: Double = 0
    var longitude: Double = 0
}

struct MethodDraft: Identifiable {
    var id = UUID()
    var label = ""
    var value = ""
}

struct SocialDraft: Identifiable {
    var id = UUID()
    var platform = ""
    var value = ""
}

// MARK: - Location Search

struct LocationSearchField: View {
    @Binding var draft: LocationDraft
    @State private var searchText = ""
    @StateObject private var completer = LocationCompleter()
    @State private var isResolving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search address...", text: $searchText)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
                if isResolving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        completer.results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))

            if !draft.address.isEmpty && completer.results.isEmpty {
                Text(draft.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !completer.results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(completer.results, id: \.self) { result in
                        Button {
                            resolve(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                        if result != completer.results.last {
                            Divider()
                        }
                    }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                completer.results = []
            } else {
                completer.search(query: newValue)
            }
        }
    }

    private func resolve(_ result: MKLocalSearchCompletion) {
        isResolving = true
        let request = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            isResolving = false
            guard let item = response?.mapItems.first else { return }
            draft.address = item.placemark.formattedAddress ?? result.title
            draft.latitude = item.placemark.coordinate.latitude
            draft.longitude = item.placemark.coordinate.longitude
            if draft.label.isEmpty {
                draft.label = result.title
            }
            completer.results = []
            searchText = ""
        }
    }
}

// MARK: - MKLocalSearchCompleter wrapper

final class LocationCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func search(query: String) {
        completer.queryFragment = query
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = Array(completer.results.prefix(5))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Silently ignore — partial queries often fail briefly
    }
}

extension CLPlacemark {
    var formattedAddress: String? {
        [subThoroughfare, thoroughfare, locality, administrativeArea, postalCode, country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

// MARK: - Flow Layout for tag chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
