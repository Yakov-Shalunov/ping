import SwiftData
import Foundation

enum ContactMethodType: String, Codable, CaseIterable, Identifiable {
    case phone
    case email
    case social

    var id: String { rawValue }

    var label: String {
        switch self {
        case .phone: "Phone"
        case .email: "Email"
        case .social: "Social"
        }
    }

    var systemImage: String {
        switch self {
        case .phone: "phone.fill"
        case .email: "envelope.fill"
        case .social: "link"
        }
    }
}

@Model
final class ContactMethod {
    var id: UUID = UUID()
    var typeRaw: String = ContactMethodType.phone.rawValue
    var value: String = ""
    var label: String?
    var platform: String?
    var contact: Contact?

    var type: ContactMethodType {
        get { ContactMethodType(rawValue: typeRaw) ?? .phone }
        set { typeRaw = newValue.rawValue }
    }

    init(type: ContactMethodType, value: String, label: String? = nil, platform: String? = nil) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.value = value
        self.label = label
        self.platform = platform
    }
}
