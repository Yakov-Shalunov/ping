import SwiftUI
import SwiftData

struct TidyUpView: View {
    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: [SortDescriptor(\Contact.firstName, comparator: .localized)]) private var contacts: [Contact]

    /// Single-pass computation of all missing-field data.
    private var fieldStats: (missingByField: [(field: TrackedField, contacts: [Contact])], totalMissing: Int) {
        var result: [(field: TrackedField, contacts: [Contact])] = []
        var totalMissing = 0
        for field in TrackedField.allCases {
            let missing = contacts.filter { field.isMissing(for: $0) }
            result.append((field, missing))
            totalMissing += missing.count
        }
        return (result, totalMissing)
    }

    var body: some View {
        let stats = fieldStats
        let totalFields = contacts.count * TrackedField.allCases.count
        let filledFields = totalFields - stats.totalMissing
        let completionPercent = totalFields > 0 ? Double(filledFields) / Double(totalFields) : 1.0

        List {
            Section {
                VStack(spacing: 8) {
                    ProgressView(value: completionPercent) {
                        Text("\(Int(completionPercent * 100))% complete")
                            .font(.headline)
                    }
                    Text("\(filledFields) of \(totalFields) fields filled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Missing Fields") {
                ForEach(stats.missingByField, id: \.field) { entry in
                    if !entry.contacts.isEmpty {
                        NavigationLink {
                            TidyUpCardFlow(field: entry.field, contacts: entry.contacts)
                        } label: {
                            Label {
                                HStack {
                                    Text(entry.field.label)
                                    Spacer()
                                    Text("\(entry.contacts.count) missing")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: entry.field.systemImage)
                            }
                        }
                    }
                }
            }

            if stats.totalMissing == 0 {
                ContentUnavailableView {
                    Label("All Done", systemImage: "checkmark.circle")
                } description: {
                    Text("All your contacts have complete information.")
                }
            }
        }
        .navigationTitle("Tidy Up")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .listStyle(.inset)
        #endif
    }
}

// MARK: - Card Flow

struct TidyUpCardFlow: View {
    let field: TrackedField
    @State private var contacts: [Contact]

    @Environment(\.modelContext) private var modelContext
    @Environment(SaveErrorManager.self) private var saveErrorManager
    @State private var currentIndex = 0
    @State private var skippedCount = 0

    init(field: TrackedField, contacts: [Contact]) {
        self.field = field
        self._contacts = State(initialValue: contacts)
    }

    private var currentContact: Contact? {
        guard currentIndex < contacts.count else { return nil }
        return contacts[currentIndex]
    }

    var body: some View {
        VStack {
            if let contact = currentContact {
                Text("\(currentIndex + 1) of \(contacts.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top)

                ContactAvatar(contact: contact, size: 64)
                    .padding(.top, 8)
                Text(contact.displayName)
                    .font(.title3)
                    .fontWeight(.semibold)
                if !contact.affiliations.isEmpty {
                    Text(contact.affiliations.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !(contact.tags ?? []).isEmpty {
                    HStack(spacing: 6) {
                        ForEach((contact.tags ?? []).prefix(3)) { tag in
                            Text(tag.name)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(tag.color.opacity(0.15))
                                .foregroundStyle(tag.color)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                fieldInput(for: contact)

                Spacer()
                Spacer()

                HStack(spacing: 16) {
                    Button { skip() } label: {
                        Text("Skip")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button { markNA(contact) } label: {
                        Text("N/A")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom)

            } else {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                Text("All done!")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Filled \(contacts.count - skippedCount) of \(contacts.count)")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .navigationTitle(field.label)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func fieldInput(for contact: Contact) -> some View {
        switch field {
        case .location:
            LocationTidyCard(contact: contact) { mutation in advanceAndSave(for: contact, applying: mutation) }
        case .email:
            MethodTidyCard(contact: contact, methodType: .email, prompt: "Email address") { mutation in advanceAndSave(for: contact, applying: mutation) }
        case .phone:
            MethodTidyCard(contact: contact, methodType: .phone, prompt: "Phone number") { mutation in advanceAndSave(for: contact, applying: mutation) }
        case .checkInSchedule:
            ScheduleTidyCard(contact: contact) { mutation in advanceAndSave(for: contact, applying: mutation) }
        }
    }

    private func skip() {
        skippedCount += 1
        advance()
    }

    private func advance() {
        withAnimation {
            currentIndex += 1
        }
    }

    private func advanceAndSave(for contact: Contact, applying mutation: @escaping () -> Void) {
        let name = contact.displayName
        advance()
        saveErrorManager.backgroundSave(modelContext, contactName: name, applying: mutation)
    }

    private func markNA(_ contact: Contact) {
        let fieldRaw = field.rawValue
        advanceAndSave(for: contact) {
            let status = FieldStatus(fieldName: fieldRaw, status: .notApplicable)
            status.contact = contact
            contact.fieldStatuses?.append(status)
        }
    }
}

// MARK: - Tidy Card Types

private struct LocationTidyCard: View {
    let contact: Contact
    let onSave: (@escaping () -> Void) -> Void
    @State private var draft = LocationDraft()

    var body: some View {
        VStack(spacing: 12) {
            Text("Where does \(contact.firstName.isEmpty ? contact.displayName : contact.firstName) live?")
                .font(.headline)

            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                TextField("Label (e.g. Home in NYC)", text: $draft.label)
            }
            .padding(10)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)

            LocationSearchField(draft: $draft)
                .padding(.horizontal)

            Button("Save & Next") {
                guard !draft.label.isEmpty else { return }
                let label = draft.label, address = draft.address, lat = draft.latitude, lng = draft.longitude
                onSave {
                    let loc = Location(label: label, address: address.isEmpty ? nil : address,
                                       latitude: lat, longitude: lng)
                    loc.contact = contact
                    contact.locations?.append(loc)
                    contact.updatedAt = Date()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.label.isEmpty)
        }
    }
}

private struct MethodTidyCard: View {
    let contact: Contact
    let methodType: ContactMethodType
    let prompt: String
    let onSave: (@escaping () -> Void) -> Void
    @State private var value = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("What's \(contact.firstName.isEmpty ? contact.displayName : contact.firstName)'s \(prompt.lowercased())?")
                .font(.headline)

            HStack(spacing: 8) {
                Image(systemName: methodType.systemImage)
                    .foregroundStyle(.secondary)
                TextField(prompt, text: $value)
                    #if os(iOS)
                    .keyboardType(methodType == .phone ? .phonePad : .emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            .padding(10)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)

            Button("Save & Next") {
                guard !value.isEmpty else { return }
                let val = value
                let mt = methodType
                onSave {
                    let method = ContactMethod(type: mt, value: val)
                    method.contact = contact
                    contact.contactMethods?.append(method)
                    contact.updatedAt = Date()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(value.isEmpty)
        }
    }
}

private struct ScheduleTidyCard: View {
    let contact: Contact
    let onSave: (@escaping () -> Void) -> Void
    @State private var weeks: Int = 4

    var body: some View {
        VStack(spacing: 12) {
            Text("How often to check in with \(contact.firstName.isEmpty ? contact.displayName : contact.firstName)?")
                .font(.headline)

            Picker("Frequency", selection: $weeks) {
                Text("Every week").tag(1)
                Text("Every 2 weeks").tag(2)
                Text("Every 3 weeks").tag(3)
                Text("Every month").tag(4)
                Text("Every 2 months").tag(8)
                Text("Every 3 months").tag(13)
            }
            #if os(iOS)
            .pickerStyle(.wheel)
            .frame(height: 120)
            #endif

            Button("Save & Next") {
                let w = weeks
                onSave {
                    contact.checkInIntervalDays = w * 7
                    contact.updatedAt = Date()
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Disable check-ins") {
                onSave {
                    contact.checkInDisabled = true
                    contact.updatedAt = Date()
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}
