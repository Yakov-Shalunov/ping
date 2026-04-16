# Ping — Contact Reminder App

A personal iOS/macOS app for staying in touch with your network. Tracks 50–200 contacts with recurring check-in reminders, a trip-planning map view, contacts import, and a "tidy up" workflow for filling in missing data.

## Features

- **People list** with search, tag filtering, and sort options
- **Check-in reminders** — overdue/upcoming sections, snooze, structured logging (call, text, in-person, etc.)
- **Map view** — MapKit with city search, tag filtering, and contact cards
- **Contacts import** — pull from phone contacts with dedup on re-import
- **Tidy Up** — card-based flow for filling in missing locations, emails, phone numbers, and schedules
- **Calendar sync** — syncs check-in reminders to a dedicated "Ping Check-ins" calendar via EventKit

## Tech Stack

- **SwiftUI** — all UI, multiplatform (iOS primary, macOS secondary)
- **SwiftData** — local persistence
- **MapKit** — map view with city search
- **EventKit** — calendar sync
- **Contacts framework** — phone contacts import
- **xcodegen** — project generation from `project.yml`

## Setup

1. Install [xcodegen](https://github.com/yonaskolb/XcodeGen):
   ```bash
   brew install xcodegen
   ```

2. Create your local environment file:
   ```bash
   cp env.sh.example env.sh
   ```
   Edit `env.sh` and set your Apple Development Team ID.

3. Generate the Xcode project and build:
   ```bash
   ./build.sh          # builds for macOS
   ./build.sh iOS      # builds for iOS Simulator (iPhone 16)
   ./build.sh iOS "iPhone 15 Pro"  # specify simulator device
   ```

   Or manually:
   ```bash
   source env.sh
   xcodegen generate
   xcodebuild -project Ping.xcodeproj -scheme Ping -destination 'platform=macOS' build
   ```

## Project Structure

```
Ping/
├── PingApp.swift              # App entry, ModelContainer setup
├── ContentView.swift          # 3-tab shell (People, Check-ins, Map)
├── Models/                    # SwiftData models (Contact, Location, Tag, etc.)
├── Views/
│   ├── PeopleListView.swift   # Search, tag filter, sort, settings
│   ├── PersonDetailView.swift # Full contact profile, check-in history
│   ├── AddEditContactView.swift
│   ├── CheckInsListView.swift # Overdue/upcoming/maybe-reach-out sections
│   ├── ContactMapView.swift   # MapKit with city search and tag filtering
│   ├── TidyUpView.swift       # Card flow for missing fields
│   └── ...
├── CalendarSyncManager.swift  # EventKit calendar sync
├── Geocoder.swift             # Rate-limited geocoding for imported addresses
└── Info.plist
project.yml                    # xcodegen project spec
build.sh                       # Build script (sources env.sh, runs xcodegen + xcodebuild)
env.sh.example                 # Template for local env config
```
