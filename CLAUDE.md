# Ping — Contact Reminder App

## Project Overview
A personal iOS/macOS app for managing a network of 50–200 people. Core features: recurring check-in reminders, trip-planning map view, contacts import, and a "tidy up" workflow for filling in missing data. Sideloaded onto user's phone, not published to App Store.

## Tech Stack
- **SwiftUI** — all UI, multiplatform (iOS primary, macOS secondary)
- **SwiftData** — local persistence (CloudKit sync planned but not yet wired)
- **MapKit** — map view with city search
- **EventKit** — calendar sync to dedicated "Ping Check-ins" calendar
- **Contacts framework** — import from phone contacts
- **xcodegen** — project generation from `project.yml` (run `xcodegen generate` after modifying project config or adding/removing files)

## Building
```bash
xcodegen generate   # regenerate .xcodeproj from project.yml
xcodebuild -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
# or for iOS:
xcodebuild -project Ping.xcodeproj -scheme Ping -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO build
```
Both iOS and macOS SDKs are installed.

**Known issue:** `.foregroundStyle(.accentColor)` doesn't compile — use `Color.accentColor` instead.

## Architecture

### Data Model (SwiftData, all in `Ping/Models/`)
- **Contact** — core entity. Check-in schedule is inline (`checkInIntervalDays: Int?`, `checkInDisabled: Bool`, `snoozedUntil: Date?`). Computed properties for `nextDueDate()`, `daysOverdue()`, `hasExplicitSchedule`, `isSnoozed`.
- **Location** — one-to-many from Contact. Has label, address, lat/long coordinates.
- **Tag** — many-to-many with Contact. Only one side has `@Relationship(inverse:)` (on Contact) to avoid circular macro reference.
- **ContactMethod** — phone/email/social with enum type stored as raw string.
- **CheckIn** — structured log entry: date, type (text/call/video/inPerson/socialMedia/other), optional note.
- **FieldStatus** — tracks fields explicitly marked "unknown" or "N/A" per contact.

App settings (globalCheckInIntervalDays, calendarSyncEnabled) use `@AppStorage`, not SwiftData.

### Check-in Schedule Design (hybrid)
- Contacts with explicit `checkInIntervalDays` → appear in main Check-ins sections, sync to calendar
- Contacts without explicit schedule → appear in "Maybe Reach Out" if past the global default interval
- `checkInDisabled = true` → excluded from all lists
- `snoozedUntil` → pushes the due date forward without creating fake check-in entries

### Key Files
- `PingApp.swift` — app entry, ModelContainer setup, CalendarSyncManager as environment object
- `ContentView.swift` — 3-tab shell (People, Check-ins, Map), overdue badge, launch-time geocoding + calendar sync
- `PeopleListView.swift` — search, tag filter chips, sort options, settings gear
- `PersonDetailView.swift` — full contact profile; also contains `LogCheckInSheet`, `CheckInHistoryRow`, `FullCheckInHistoryView`
- `AddEditContactView.swift` — contact form with location search (MKLocalSearch), tag management, `FlowLayout` for tag chips
- `PersonRowView.swift` — list row; also contains `ContactAvatar` and cross-platform image helpers (`PlatformImage`)
- `CheckInsListView.swift` — overdue/this week/upcoming/maybe reach out sections, `SnoozeSheet`
- `ContactMapView.swift` — MapKit with city search, tag filtering, contact card with check-in action
- `SettingsView.swift` — global defaults, calendar sync toggle + authorization, import button, tag manager
- `ImportContactsView.swift` — contacts permission, selectable list, dedup on re-import, background geocoding
- `TidyUpView.swift` — completion progress, card-based flow for missing fields (location/email/phone/schedule)
- `CalendarSyncManager.swift` — EventKit service: creates "Ping Check-ins" calendar, syncs all-day events
- `Geocoder.swift` — rate-limited CLGeocoder for filling in coordinates on imported addresses

## Implementation Status (as of 2026-04-14)

### Complete (Phases 1–5)
- [x] SwiftData models with all relationships
- [x] People list with search, tag filtering, sort options
- [x] Person detail view with locations mini-map, check-in history, contact info
- [x] Add/edit contact form with MapKit location search
- [x] Tag management (create, assign, filter, delete)
- [x] Check-ins tab with overdue/upcoming sections + "Maybe Reach Out"
- [x] Structured check-in logging (type + date + note)
- [x] Snooze with duration picker (1d/3d/1w/2w) using `snoozedUntil` field
- [x] Overdue badge on Check-ins tab
- [x] Full check-in history with delete capability
- [x] Map with city search, tag filtering, contact card, "Log Check-in" action
- [x] Contacts import with dedup on re-import
- [x] Background geocoding of imported addresses
- [x] Tidy Up card flow for missing fields (location, email, phone, schedule)
- [x] EventKit calendar sync (dedicated calendar, sync on launch/check-in/snooze)
- [x] Settings with calendar authorization flow, sync status, import entry

### Not Yet Built
- [ ] CloudKit sync (SwiftData ModelConfiguration with `.cloudKitDatabase(.automatic)`)
- [ ] macOS polish (currently builds but may have layout issues)
- [ ] Calendar-aware trips (read travel events, surface nearby contacts)
- [ ] Share sheet extension (save social links from Safari)
- [ ] Widgets (overdue check-ins, nearby contacts)

## Design Document
Full design spec with ASCII UI mockups is at `.claude/plans/binary-inventing-flurry.md`.
