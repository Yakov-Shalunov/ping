import SwiftUI
import SwiftData

struct TidyUpView: View {
    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.firstName) private var contacts: [Contact]

    private var totalFields: Int {
        contacts.count * TrackedField.allCases.count
    }

    private var filledFields: Int {
        totalFields - TrackedField.allCases.reduce(0) { total, field in
            total + contacts.filter { field.isMissing(for: $0) }.count
        }
    }

    private var completionPercent: Double {
        guard totalFields > 0 else { return 1 }
        return Double(filledFields) / Double(totalFields)
    }

    var body: some View {
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
                ForEach(TrackedField.allCases) { field in
                    let missing = contacts.filter { field.isMissing(for: $0) }
                    if !missing.isEmpty {
                        NavigationLink {
                            TidyUpCardFlow(field: field, contacts: missing)
                        } label: {
                            Label {
                                HStack {
                                    Text(field.label)
                                    Spacer()
                                    Text("\(missing.count) missing")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: field.systemImage)
                            }
                        }
                    }
                }
            }

            if TrackedField.allCases.allSatisfy({ field in contacts.allSatisfy { !field.isMissing(for: $0) } }) {
                ContentUnavailableView {
                    Label("All Done", systemImage: "checkmark.circle")
                } description: {
                    Text("All your contacts have complete information.")
                }
            }
        }
        .navigationTitle("Tidy Up")
    }
}

// MARK: - Card Flow

struct TidyUpCardFlow: View {
    let field: TrackedField
    let contacts: [Contact]

    @Environment(\.modelContext) private var modelContext
    @State private var currentIndex = 0
    @State private var skippedCount = 0

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
            LocationTidyCard(contact: contact) { advance() }
        case .email:
            MethodTidyCard(contact: contact, methodType: .email, prompt: "Email address") { advance() }
        case .phone:
            MethodTidyCard(contact: contact, methodType: .phone, prompt: "Phone number") { advance() }
        case .checkInSchedule:
            ScheduleTidyCard(contact: contact) { advance() }
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

    private func markNA(_ contact: Contact) {
        let status = FieldStatus(fieldName: field.rawValue, status: .notApplicable)
        status.contact = contact
        contact.fieldStatuses?.append(status)
        advance()
    }
}

// MARK: - Tidy Card Types

private struct LocationTidyCard: View {
    let contact: Contact
    let onSave: () -> Void
    @Environment(\.modelContext) private var modelContext
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
                let loc = Location(label: draft.label, address: draft.address.isEmpty ? nil : draft.address,
                                   latitude: draft.latitude, longitude: draft.longitude)
                loc.contact = contact
                contact.locations?.append(loc)
                contact.updatedAt = Date()
                onSave()
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
    let onSave: () -> Void
    @Environment(\.modelContext) private var modelContext
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
                let method = ContactMethod(type: methodType, value: value)
                method.contact = contact
                contact.contactMethods?.append(method)
                contact.updatedAt = Date()
                onSave()
            }
            .buttonStyle(.borderedProminent)
            .disabled(value.isEmpty)
        }
    }
}

private struct ScheduleTidyCard: View {
    let contact: Contact
    let onSave: () -> Void
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
                contact.checkInIntervalDays = weeks * 7
                contact.updatedAt = Date()
                onSave()
            }
            .buttonStyle(.borderedProminent)

            Button("Disable check-ins") {
                contact.checkInDisabled = true
                contact.updatedAt = Date()
                onSave()
            }
            .foregroundStyle(.secondary)
        }
    }
}
