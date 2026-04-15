import SwiftData
import Foundation

enum CheckInType: String, Codable, CaseIterable, Identifiable {
    case text
    case call
    case videoCall
    case inPerson
    case socialMedia
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: "Text"
        case .call: "Call"
        case .videoCall: "Video Call"
        case .inPerson: "In Person"
        case .socialMedia: "Social Media"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "message.fill"
        case .call: "phone.fill"
        case .videoCall: "video.fill"
        case .inPerson: "person.2.fill"
        case .socialMedia: "globe"
        case .other: "ellipsis.circle.fill"
        }
    }
}

@Model
final class CheckIn {
    var id: UUID = UUID()
    var date: Date = Date()
    var typeRaw: String = CheckInType.other.rawValue
    var note: String?
    var contact: Contact?

    var type: CheckInType {
        get { CheckInType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    init(date: Date = Date(), type: CheckInType = .other, note: String? = nil) {
        self.id = UUID()
        self.date = date
        self.typeRaw = type.rawValue
        self.note = note
    }
}
