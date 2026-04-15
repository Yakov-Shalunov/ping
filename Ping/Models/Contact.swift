import SwiftData
import Foundation

@Model
final class Contact {
    var id: UUID = UUID()
    var firstName: String = ""
    var lastName: String = ""
    var nickname: String?
    var photoData: Data?
    var notes: String?
    var affiliations: [String] = []

    // Check-in schedule (inline — no separate model needed)
    // nil = use global default, non-nil = custom interval in days
    var checkInIntervalDays: Int?
    // If true, this contact never appears in check-in lists
    var checkInDisabled: Bool = false
    // If set, the contact's next due date is pushed to at least this date
    var snoozedUntil: Date?

    @Relationship(deleteRule: .cascade, inverse: \Location.contact)
    var locations: [Location]?

    @Relationship(deleteRule: .cascade, inverse: \ContactMethod.contact)
    var contactMethods: [ContactMethod]?

    @Relationship(deleteRule: .cascade, inverse: \CheckIn.contact)
    var checkIns: [CheckIn]?

    @Relationship(inverse: \Tag.contacts)
    var tags: [Tag]?

    @Relationship(deleteRule: .cascade, inverse: \FieldStatus.contact)
    var fieldStatuses: [FieldStatus]?

    var isArchived: Bool = false

    var importedContactID: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var displayName: String {
        let full = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        if !full.isEmpty { return full }
        return nickname ?? "Unknown"
    }

    var locationSummary: String {
        (locations ?? []).map(\.label).joined(separator: " \u{00B7} ")
    }

    var sortedCheckIns: [CheckIn] {
        (checkIns ?? []).sorted { $0.date > $1.date }
    }

    var lastCheckIn: CheckIn? {
        (checkIns ?? []).max(by: { $0.date < $1.date })
    }

    /// The effective check-in interval for this contact, considering the global default.
    func effectiveIntervalDays(globalDefault: Int) -> Int? {
        if checkInDisabled { return nil }
        return checkInIntervalDays ?? globalDefault
    }

    /// The next check-in due date, or nil if no schedule.
    /// If snoozed, the due date is pushed to at least the snooze expiry.
    func nextDueDate(globalDefault: Int) -> Date? {
        guard let interval = effectiveIntervalDays(globalDefault: globalDefault) else { return nil }
        let anchor = lastCheckIn?.date ?? createdAt
        guard let scheduledDate = Calendar.current.date(byAdding: .day, value: interval, to: anchor) else { return nil }
        if let snooze = snoozedUntil, snooze > scheduledDate {
            return snooze
        }
        return scheduledDate
    }

    /// Whether this contact is currently snoozed.
    var isSnoozed: Bool {
        guard let snooze = snoozedUntil else { return false }
        return snooze > Date()
    }

    /// How many days overdue (positive) or until due (negative). Nil if no schedule.
    func daysOverdue(globalDefault: Int) -> Int? {
        guard let dueDate = nextDueDate(globalDefault: globalDefault) else { return nil }
        return Calendar.current.dateComponents([.day], from: dueDate, to: Date()).day
    }

    /// Whether this contact has an explicitly set per-person schedule (not just the global default).
    var hasExplicitSchedule: Bool {
        checkInIntervalDays != nil && !checkInDisabled
    }

    init(firstName: String = "", lastName: String = "", nickname: String? = nil) {
        self.id = UUID()
        self.firstName = firstName
        self.lastName = lastName
        self.nickname = nickname
        self.locations = []
        self.contactMethods = []
        self.checkIns = []
        self.tags = []
        self.fieldStatuses = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
