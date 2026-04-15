import EventKit
import SwiftData
import Foundation

/// Manages syncing check-in reminders to a dedicated system calendar via EventKit.
///
/// Each contact with an explicit check-in schedule gets one all-day event on their next due date.
/// When a check-in is logged, the old event is removed and a new one is created for the next due date.
@MainActor
final class CalendarSyncManager: ObservableObject {
    static let calendarTitle = "Ping Check-ins"

    private let store = EKEventStore()
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var lastSyncDate: Date?

    init() {
        refreshAuthStatus()
    }

    func refreshAuthStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Authorization

    func requestAccess() async -> Bool {
        do {
            let granted: Bool
            if #available(iOS 17.0, macOS 14.0, *) {
                granted = try await store.requestFullAccessToEvents()
            } else {
                granted = try await store.requestAccess(to: .event)
            }
            refreshAuthStatus()
            return granted
        } catch {
            refreshAuthStatus()
            return false
        }
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .fullAccess, .authorized:
            return true
        default:
            return false
        }
    }

    // MARK: - Calendar Management

    /// Find or create the "Ping Check-ins" calendar.
    private func findOrCreateCalendar() -> EKCalendar? {
        // Look for existing calendar
        let calendars = store.calendars(for: .event)
        if let existing = calendars.first(where: { $0.title == Self.calendarTitle }) {
            return existing
        }

        // Create new calendar
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.calendarTitle

        // Pick a source that supports adding calendars.
        // Prefer iCloud (calDAV), then local, then the default calendar's source as fallback.
        if let calDAVSource = store.sources.first(where: { $0.sourceType == .calDAV }) {
            calendar.source = calDAVSource
        } else if let localSource = store.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else if let defaultSource = store.defaultCalendarForNewEvents?.source {
            calendar.source = defaultSource
        } else {
            return nil
        }

        do {
            try store.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            print("Failed to save calendar: \(error.localizedDescription)")
            // If the chosen source failed, try remaining sources
            for source in store.sources where source != calendar.source {
                calendar.source = source
                do {
                    try store.saveCalendar(calendar, commit: true)
                    return calendar
                } catch {
                    continue
                }
            }
            print("Could not create Ping calendar with any available source")
            return nil
        }
    }

    // MARK: - Sync

    /// Full sync: creates/updates/removes events for all contacts with explicit schedules.
    func syncAll(context: ModelContext, globalDefault: Int) {
        guard isAuthorized else { return }
        guard let calendar = findOrCreateCalendar() else { return }

        let descriptor = FetchDescriptor<Contact>()
        guard let contacts = try? context.fetch(descriptor) else { return }

        // Get all existing events in our calendar (next 365 days)
        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Calendar.current.date(byAdding: .year, value: 1, to: startDate) ?? startDate
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendar])
        let existingEvents = store.events(matching: predicate)

        // Build a map of contact ID → existing event (stored in event notes)
        var eventsByContactID: [String: EKEvent] = [:]
        for event in existingEvents {
            if let contactID = event.notes {
                eventsByContactID[contactID] = event
            }
        }

        // Sync each contact
        for contact in contacts {
            let contactIDString = contact.id.uuidString
            let existingEvent = eventsByContactID.removeValue(forKey: contactIDString)

            guard contact.hasExplicitSchedule,
                  let dueDate = contact.nextDueDate(globalDefault: globalDefault) else {
                // No schedule — remove any existing event
                if let event = existingEvent {
                    try? store.remove(event, span: .thisEvent)
                }
                continue
            }

            let dueDayStart = Calendar.current.startOfDay(for: dueDate)
            let title = "Check in with \(contact.displayName)"

            if let event = existingEvent {
                // Update if date or title changed
                if event.startDate != dueDayStart || event.title != title {
                    event.title = title
                    event.startDate = dueDayStart
                    event.endDate = dueDayStart
                    event.isAllDay = true
                    try? store.save(event, span: .thisEvent)
                }
            } else {
                // Create new event
                let event = EKEvent(eventStore: store)
                event.title = title
                event.startDate = dueDayStart
                event.endDate = dueDayStart
                event.isAllDay = true
                event.calendar = calendar
                event.notes = contactIDString // Store contact ID for matching
                try? store.save(event, span: .thisEvent)
            }
        }

        // Remove orphaned events (contacts that no longer have schedules or were deleted)
        for (_, orphanEvent) in eventsByContactID {
            try? store.remove(orphanEvent, span: .thisEvent)
        }

        try? store.commit()
        lastSyncDate = Date()
    }

    /// Quick sync for a single contact after a check-in or schedule change.
    func syncContact(_ contact: Contact, globalDefault: Int) {
        guard isAuthorized else { return }
        guard let calendar = findOrCreateCalendar() else { return }

        let contactIDString = contact.id.uuidString

        // Find existing event for this contact
        let startDate = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendar])
        let existingEvents = store.events(matching: predicate)
        let existingEvent = existingEvents.first { $0.notes == contactIDString }

        // Remove old event
        if let event = existingEvent {
            try? store.remove(event, span: .thisEvent, commit: true)
        }

        // Create new event if contact has a schedule
        guard contact.hasExplicitSchedule,
              let dueDate = contact.nextDueDate(globalDefault: globalDefault) else { return }

        let dueDayStart = Calendar.current.startOfDay(for: dueDate)
        let event = EKEvent(eventStore: store)
        event.title = "Check in with \(contact.displayName)"
        event.startDate = dueDayStart
        event.endDate = dueDayStart
        event.isAllDay = true
        event.calendar = calendar
        event.notes = contactIDString
        try? store.save(event, span: .thisEvent, commit: true)
    }

    /// Remove all events from the Ping calendar.
    func removeAllEvents() {
        guard isAuthorized else { return }
        guard let calendar = findOrCreateCalendar() else { return }

        let startDate = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendar])
        let events = store.events(matching: predicate)
        for event in events {
            try? store.remove(event, span: .thisEvent)
        }
        try? store.commit()
    }
}
