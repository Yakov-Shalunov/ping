import Contacts
import Foundation
import SwiftData

/// Pulls changes from system Contacts into Ping.
/// Updates existing linked contacts and imports new contacts automatically.
@MainActor
final class ContactPullIn {
    private let store = CNContactStore()

    /// Whether we have read access to contacts.
    var isAuthorized: Bool {
        ContactsAccess.from(CNContactStore.authorizationStatus(for: .contacts)) == .authorized
    }

    /// Pull in changes from system Contacts.
    /// - Returns: (updated, created) counts.
    @discardableResult
    func pullIn(context: ModelContext) async -> (updated: Int, created: Int) {
        guard isAuthorized else { return (0, 0) }

        let phoneContacts = await fetchAllContacts()
        guard !phoneContacts.isEmpty else { return (0, 0) }

        // Fetch all existing Ping contacts that have an importedContactID
        let descriptor = FetchDescriptor<Contact>()
        let allContacts = (try? context.fetch(descriptor)) ?? []
        let linkedByID = Dictionary(
            allContacts.compactMap { c in c.importedContactID.map { ($0, c) } },
            uniquingKeysWith: { first, _ in first }
        )

        var updated = 0
        var created = 0

        for pc in phoneContacts {
            if let existing = linkedByID[pc.id] {
                if updateExistingContact(existing, from: pc) {
                    updated += 1
                }
            } else {
                createNewContact(from: pc, in: context)
                created += 1
            }
        }

        if updated > 0 || created > 0 {
            try? context.save()

            // Geocode any new addresses
            if created > 0 {
                let geocoder = LocationGeocoder()
                await geocoder.geocodeMissingLocations(in: context)
            }
        }

        return (updated, created)
    }

    // MARK: - Fetch

    private func fetchAllContacts() async -> [PhoneContact] {
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

        nonisolated(unsafe) let store = self.store
        return await withCheckedContinuation { continuation in
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
                        if !pc.firstName.isEmpty || !pc.lastName.isEmpty || !pc.phones.isEmpty || !pc.emails.isEmpty {
                            contacts.append(pc)
                        }
                    }
                } catch {
                    // Silently fail
                }

                continuation.resume(returning: contacts)
            }
        }
    }

    // MARK: - Update Existing

    /// Returns true if any changes were made.
    private func updateExistingContact(_ contact: Contact, from pc: PhoneContact) -> Bool {
        var changed = false

        // Update name if changed in system contacts
        if contact.firstName != pc.firstName && !pc.firstName.isEmpty {
            contact.firstName = pc.firstName
            changed = true
        }
        if contact.lastName != pc.lastName && !pc.lastName.isEmpty {
            contact.lastName = pc.lastName
            changed = true
        }
        if let nickname = contact.nickname, nickname != pc.nickname && !pc.nickname.isEmpty {
            contact.nickname = pc.nickname
            changed = true
        } else if contact.nickname == nil && !pc.nickname.isEmpty {
            contact.nickname = pc.nickname
            changed = true
        }

        // Update photo if system contact has one and ours is missing
        if contact.photoData == nil, let photo = pc.imageData ?? pc.thumbnailData {
            contact.photoData = photo
            changed = true
        }

        // Update company if system contact has one and ours is empty
        if contact.affiliations.isEmpty && !pc.company.isEmpty {
            contact.affiliations = [pc.company]
            changed = true
        }

        // Add new phone numbers
        let existingPhones = Set((contact.contactMethods ?? []).filter { $0.type == .phone }.map(\.value))
        for phone in pc.phones where !existingPhones.contains(phone.value) {
            let method = ContactMethod(type: .phone, value: phone.value, label: phone.label)
            method.contact = contact
            contact.contactMethods?.append(method)
            changed = true
        }

        // Add new emails
        let existingEmails = Set((contact.contactMethods ?? []).filter { $0.type == .email }.map(\.value))
        for email in pc.emails where !existingEmails.contains(email.value) {
            let method = ContactMethod(type: .email, value: email.value, label: email.label)
            method.contact = contact
            contact.contactMethods?.append(method)
            changed = true
        }

        // Add new social profiles
        let existingSocials = Set((contact.contactMethods ?? []).filter { $0.type == .social }.map(\.value))
        for social in pc.socialProfiles where !social.value.isEmpty && !existingSocials.contains(social.value) {
            let method = ContactMethod(type: .social, value: social.value, platform: social.platform)
            method.contact = contact
            contact.contactMethods?.append(method)
            changed = true
        }

        // Add new addresses if contact has none
        if (contact.locations ?? []).isEmpty {
            for addr in pc.addresses where !addr.formatted.isEmpty {
                let loc = Location(label: addr.label ?? "Address", address: addr.formatted)
                loc.contact = contact
                contact.locations?.append(loc)
                changed = true
            }
        }

        if changed {
            contact.updatedAt = Date()
        }
        return changed
    }

    // MARK: - Create New

    private func createNewContact(from pc: PhoneContact, in context: ModelContext) {
        let contact = Contact(firstName: pc.firstName, lastName: pc.lastName,
                              nickname: pc.nickname.isEmpty ? nil : pc.nickname)
        contact.importedContactID = pc.id
        contact.photoData = pc.imageData ?? pc.thumbnailData
        if !pc.company.isEmpty {
            contact.affiliations = [pc.company]
        }

        for phone in pc.phones {
            let method = ContactMethod(type: .phone, value: phone.value, label: phone.label)
            method.contact = contact
            contact.contactMethods?.append(method)
        }

        for email in pc.emails {
            let method = ContactMethod(type: .email, value: email.value, label: email.label)
            method.contact = contact
            contact.contactMethods?.append(method)
        }

        for social in pc.socialProfiles where !social.value.isEmpty {
            let method = ContactMethod(type: .social, value: social.value, platform: social.platform)
            method.contact = contact
            contact.contactMethods?.append(method)
        }

        for addr in pc.addresses where !addr.formatted.isEmpty {
            let loc = Location(label: addr.label ?? "Address", address: addr.formatted)
            loc.contact = contact
            contact.locations?.append(loc)
        }

        context.insert(contact)
    }
}
