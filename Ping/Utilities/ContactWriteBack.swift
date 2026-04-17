import Contacts
import Foundation

/// Writes Ping contact data back to the system Contacts app.
/// Handles both updating existing linked contacts and creating new ones.
final class ContactWriteBack {
    private let store = CNContactStore()

    enum WriteBackError: Error {
        case notAuthorized
        case contactNotFound
        case saveFailed(Error)
    }

    /// Check if we have write access to contacts.
    var isAuthorized: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    /// Request contacts access if not already granted.
    func requestAccess() async -> Bool {
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            return false
        }
    }

    /// Write a Ping contact back to the system Contacts app.
    /// For linked contacts (importedContactID set), overwrites names (first/last/nickname)
    /// if they differ, and adds any new phones, emails, addresses, socials, photo, or
    /// organization that the system contact is missing. Existing non-name data is never
    /// removed or overwritten.
    /// For unlinked contacts, creates a new system contact.
    @discardableResult
    func writeBack(_ contact: Contact) throws -> String {
        if let existingID = contact.importedContactID {
            do {
                try addNewFields(contactID: existingID, from: contact)
                return existingID
            } catch WriteBackError.contactNotFound {
                // System contact was deleted — create a new one
                return try createNew(from: contact)
            }
        } else {
            return try createNew(from: contact)
        }
    }

    // MARK: - Add New Fields (overwrites names, additive for everything else)

    private func addNewFields(contactID: String, from contact: Contact) throws {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactPostalAddressesKey,
            CNContactSocialProfilesKey,
            CNContactImageDataKey,
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactNicknameKey,
            CNContactOrganizationNameKey,
        ] as [CNKeyDescriptor]

        guard let cnContact = try? store.unifiedContact(withIdentifier: contactID, keysToFetch: keysToFetch) else {
            throw WriteBackError.contactNotFound
        }

        guard let mutable = cnContact.mutableCopy() as? CNMutableContact else {
            throw WriteBackError.contactNotFound
        }

        var changed = false
        
        // Overwrite name pieces if they differ — matches pull-in semantics
        if !contact.firstName.isEmpty, mutable.givenName != contact.firstName {
            mutable.givenName = contact.firstName
            changed = true
        }
        if !contact.lastName.isEmpty, mutable.familyName != contact.lastName  {
            mutable.familyName = contact.lastName
            changed = true
        }
        if let nickname = contact.nickname, !nickname.isEmpty, mutable.nickname != nickname {
            mutable.nickname = nickname
            changed = true
        }
        
        // Add last affiliation as company if one is not present
        if mutable.organizationName.isEmpty, !contact.affiliations.isEmpty, let lastAffiliation = contact.affiliations.last {
            mutable.organizationName = lastAffiliation
            changed = true
        }

        // Add photo only if the system contact has none
        if mutable.imageData == nil, let photoData = contact.photoData {
            mutable.imageData = photoData
            changed = true
        }

        // Add phone numbers not already present
        let existingPhones = Set(mutable.phoneNumbers.map { $0.value.stringValue })
        let pingPhones = (contact.contactMethods ?? []).filter { $0.type == .phone }
        for method in pingPhones where !existingPhones.contains(method.value) {
            let label = cnLabelForString(method.label, type: .phone)
            mutable.phoneNumbers.append(
                CNLabeledValue(label: label, value: CNPhoneNumber(stringValue: method.value))
            )
            changed = true
        }

        // Add emails not already present
        let existingEmails = Set(mutable.emailAddresses.map { $0.value as String })
        let pingEmails = (contact.contactMethods ?? []).filter { $0.type == .email }
        for method in pingEmails where !existingEmails.contains(method.value) {
            let label = cnLabelForString(method.label, type: .email)
            mutable.emailAddresses.append(
                CNLabeledValue(label: label, value: method.value as NSString)
            )
            changed = true
        }

        // Add addresses not already present (compare on street text)
        let existingAddresses = Set(mutable.postalAddresses.map { $0.value.street })
        let pingLocations = contact.locations ?? []
        for location in pingLocations {
            guard let address = location.address, !address.isEmpty,
                  !existingAddresses.contains(address) else { continue }
            let postal = CNMutablePostalAddress()
            postal.street = address
            let label = cnLabelForString(location.label, type: .address)
            mutable.postalAddresses.append(
                CNLabeledValue(label: label, value: postal)
            )
            changed = true
        }

        // Add social profiles not already present (compare on URL string)
        let existingSocials = Set(mutable.socialProfiles.map { $0.value.urlString })
        let pingSocials = (contact.contactMethods ?? []).filter { $0.type == .social }
        for method in pingSocials where !existingSocials.contains(method.value) {
            let profile = CNSocialProfile(
                urlString: method.value,
                username: nil,
                userIdentifier: nil,
                service: method.platform
            )
            mutable.socialProfiles.append(
                CNLabeledValue(label: nil, value: profile)
            )
            changed = true
        }

        guard changed else { return }

        let saveRequest = CNSaveRequest()
        saveRequest.update(mutable)
        do {
            try store.execute(saveRequest)
        } catch {
            throw WriteBackError.saveFailed(error)
        }
    }

    // MARK: - Create New

    private func createNew(from contact: Contact) throws -> String {
        let cnContact = CNMutableContact()
        applyAllFields(to: cnContact, from: contact)

        let saveRequest = CNSaveRequest()
        saveRequest.add(cnContact, toContainerWithIdentifier: nil)
        do {
            try store.execute(saveRequest)
        } catch {
            throw WriteBackError.saveFailed(error)
        }
        return cnContact.identifier
    }

    // MARK: - Apply All Fields (used only for new contacts)

    private func applyAllFields(to cnContact: CNMutableContact, from contact: Contact) {
        cnContact.givenName = contact.firstName
        cnContact.familyName = contact.lastName
        cnContact.nickname = contact.nickname ?? ""
        cnContact.organizationName = contact.affiliations.first ?? ""

        if let photoData = contact.photoData {
            cnContact.imageData = photoData
        }

        let phones = (contact.contactMethods ?? []).filter { $0.type == .phone }
        cnContact.phoneNumbers = phones.map { method in
            let label = cnLabelForString(method.label, type: .phone)
            return CNLabeledValue(label: label, value: CNPhoneNumber(stringValue: method.value))
        }

        let emails = (contact.contactMethods ?? []).filter { $0.type == .email }
        cnContact.emailAddresses = emails.map { method in
            let label = cnLabelForString(method.label, type: .email)
            return CNLabeledValue(label: label, value: method.value as NSString)
        }

        let locations = contact.locations ?? []
        cnContact.postalAddresses = locations.compactMap { location in
            guard let address = location.address, !address.isEmpty else { return nil }
            let postal = CNMutablePostalAddress()
            postal.street = address
            let label = cnLabelForString(location.label, type: .address)
            return CNLabeledValue(label: label, value: postal)
        }

        let socials = (contact.contactMethods ?? []).filter { $0.type == .social }
        cnContact.socialProfiles = socials.map { method in
            let profile = CNSocialProfile(
                urlString: method.value,
                username: nil,
                userIdentifier: nil,
                service: method.platform
            )
            return CNLabeledValue(label: nil, value: profile)
        }
    }

    // MARK: - Label Mapping

    private enum FieldType {
        case phone, email, address
    }

    private func cnLabelForString(_ label: String?, type: FieldType) -> String {
        guard let label = label?.lowercased() else {
            switch type {
            case .phone, .email: return CNLabelOther
            case .address: return CNLabelHome
            }
        }

        if label.contains("home") { return CNLabelHome }
        if label.contains("work") { return CNLabelWork }
        if label.contains("mobile") || label.contains("cell") {
            return type == .phone ? CNLabelPhoneNumberMobile : CNLabelOther
        }
        if label.contains("main") {
            return type == .phone ? CNLabelPhoneNumberMain : CNLabelOther
        }
        if label.contains("iphone") {
            return type == .phone ? CNLabelPhoneNumberiPhone : CNLabelOther
        }
        if label.contains("personal") { return CNLabelHome }

        return CNLabelOther
    }
}
