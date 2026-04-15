import SwiftData
import Foundation

enum FieldStatusType: String, Codable {
    case unknown
    case notApplicable
}

enum TrackedField: String, CaseIterable, Identifiable {
    case location
    case email
    case phone
    case checkInSchedule

    var id: String { rawValue }

    var label: String {
        switch self {
        case .location: "Location"
        case .email: "Email"
        case .phone: "Phone"
        case .checkInSchedule: "Check-in Schedule"
        }
    }

    var systemImage: String {
        switch self {
        case .location: "mappin"
        case .email: "envelope"
        case .phone: "phone"
        case .checkInSchedule: "bell"
        }
    }

    /// Checks if the given contact is missing this field (not filled in and not marked N/A or unknown).
    func isMissing(for contact: Contact) -> Bool {
        let hasStatus = (contact.fieldStatuses ?? []).contains { $0.fieldName == rawValue }
        if hasStatus { return false }

        switch self {
        case .location:
            return (contact.locations ?? []).isEmpty
        case .email:
            return !(contact.contactMethods ?? []).contains { $0.type == .email }
        case .phone:
            return !(contact.contactMethods ?? []).contains { $0.type == .phone }
        case .checkInSchedule:
            return contact.checkInIntervalDays == nil && !contact.checkInDisabled
        }
    }
}

@Model
final class FieldStatus {
    var id: UUID = UUID()
    var fieldName: String = ""
    var statusRaw: String = FieldStatusType.unknown.rawValue
    var contact: Contact?

    var status: FieldStatusType {
        get { FieldStatusType(rawValue: statusRaw) ?? .unknown }
        set { statusRaw = newValue.rawValue }
    }

    init(fieldName: String, status: FieldStatusType) {
        self.id = UUID()
        self.fieldName = fieldName
        self.statusRaw = status.rawValue
    }
}
