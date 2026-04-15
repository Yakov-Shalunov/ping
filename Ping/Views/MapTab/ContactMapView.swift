import SwiftUI
import SwiftData
import MapKit

struct ContactMapView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: [SortDescriptor(\Contact.firstName, comparator: .localized)]) private var contacts: [Contact]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var searchText = ""
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var selectedLocation: Location?
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var showingLogCheckIn: Contact?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                FilteredMapContent(
                    contacts: contacts,
                    selectedTagIDs: selectedTagIDs,
                    mapPosition: $mapPosition,
                    selectedLocation: $selectedLocation
                )

                VStack(spacing: 8) {
                    searchBar
                    if !allTags.isEmpty {
                        tagFilterBar
                    }
                    MapStatsOverlay(contacts: contacts, selectedTagIDs: selectedTagIDs)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .safeAreaInset(edge: .bottom) {
                if let location = selectedLocation, let contact = location.contact {
                    selectedContactCard(contact: contact, location: location)
                }
            }
            .navigationTitle("Map")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: Contact.self) { contact in
                PersonDetailView(contact: contact)
            }
            .sheet(item: $showingLogCheckIn) { contact in
                LogCheckInSheet(contact: contact)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search a city...", text: $searchText)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
                .onSubmit { searchCity() }
            if isSearching {
                ProgressView()
                    .scaleEffect(0.7)
            }
            if !searchText.isEmpty {
                Button { searchText = ""; searchResults = [] } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            if !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(searchResults, id: \.self) { item in
                        Button {
                            selectSearchResult(item)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.name ?? "Unknown")
                                    .font(.subheadline)
                                if let addr = item.placemark.formattedAddress {
                                    Text(addr)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .offset(y: 50)
            }
        }
        .zIndex(1)
    }

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(allTags) { tag in
                    TagChip(tag: tag, isSelected: selectedTagIDs.contains(tag.id)) {
                        if selectedTagIDs.contains(tag.id) {
                            selectedTagIDs.remove(tag.id)
                        } else {
                            selectedTagIDs.insert(tag.id)
                        }
                    }
                }
                if !selectedTagIDs.isEmpty {
                    Button("Clear") { selectedTagIDs.removeAll() }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Selected Contact Card

    private func selectedContactCard(contact: Contact, location: Location) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ContactAvatar(contact: contact, size: 50)

                VStack(alignment: .leading, spacing: 2) {
                    if !contact.affiliations.isEmpty {
                        Text(contact.affiliations.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(contact.displayName)
                        .font(.headline)
                    Text(location.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !(contact.tags ?? []).isEmpty {
                        Text((contact.tags ?? []).map(\.name).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let last = contact.lastCheckIn {
                        let days = Calendar.current.dateComponents([.day], from: last.date, to: Date()).day ?? 0
                        Text("Last check-in: \(days)d ago")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }

            HStack(spacing: 12) {
                NavigationLink(value: contact) {
                    Text("Details")
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showingLogCheckIn = contact
                } label: {
                    Text("Log Check-in")
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 8)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    // MARK: - Search

    private func searchCity() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.resultTypes = .address
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            isSearching = false
            if let items = response?.mapItems {
                searchResults = Array(items.prefix(5))
            }
        }
    }

    private func selectSearchResult(_ item: MKMapItem) {
        searchResults = []
        searchText = item.name ?? ""
        let region = MKCoordinateRegion(
            center: item.placemark.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        withAnimation {
            mapPosition = .region(region)
        }
    }
}

// MARK: - Filtered Map Content (isolated from search state)

/// A location paired with a display coordinate (possibly offset from the real coordinate to avoid overlap).
private struct PlottedLocation: Identifiable {
    let location: Location
    let displayCoordinate: CLLocationCoordinate2D
    var id: UUID { location.id }
}

/// Extracted so that search-bar keystrokes don't trigger location filtering.
private struct FilteredMapContent: View {
    let contacts: [Contact]
    let selectedTagIDs: Set<UUID>
    @Binding var mapPosition: MapCameraPosition
    @Binding var selectedLocation: Location?

    /// Spacing between spiral points in meters.
    private static let spacingMeters: Double = 30.0
    /// Golden angle in radians for Fibonacci spiral.
    private static let goldenAngle: Double = .pi * (3.0 - sqrt(5.0))

    private var plottedLocations: [PlottedLocation] {
        let filterByTags = !selectedTagIDs.isEmpty
        var locs: [Location] = []

        for contact in contacts {
            if filterByTags {
                let contactTagIDs = Set((contact.tags ?? []).map(\.id))
                if selectedTagIDs.isDisjoint(with: contactTagIDs) { continue }
            }
            for loc in contact.locations ?? [] {
                guard loc.latitude != 0 || loc.longitude != 0 else { continue }
                locs.append(loc)
            }
        }

        // Group by exact coordinates
        struct CoordinateKey: Hashable { let lat: Double; let lon: Double }
        let groups = Dictionary(grouping: locs) { CoordinateKey(lat: $0.latitude, lon: $0.longitude) }

        var result: [PlottedLocation] = []
        for (_, group) in groups {
            if group.count == 1 {
                result.append(PlottedLocation(location: group[0], displayCoordinate: group[0].coordinate))
            } else {
                let center = group[0].coordinate
                let latDegreesPerMeter = 1.0 / 111_111.0
                let lonDegreesPerMeter = 1.0 / (111_111.0 * cos(center.latitude * .pi / 180.0))

                for (i, loc) in group.enumerated() {
                    let n = Double(i)
                    let angle = n * Self.goldenAngle
                    let radius = Self.spacingMeters * sqrt(n)
                    let offsetLat = radius * cos(angle) * latDegreesPerMeter
                    let offsetLon = radius * sin(angle) * lonDegreesPerMeter
                    let coord = CLLocationCoordinate2D(
                        latitude: center.latitude + offsetLat,
                        longitude: center.longitude + offsetLon
                    )
                    result.append(PlottedLocation(location: loc, displayCoordinate: coord))
                }
            }
        }
        return result
    }

    var body: some View {
        Map(position: $mapPosition, selection: $selectedLocation) {
            ForEach(plottedLocations) { plotted in
                Marker(
                    plotted.location.contact?.displayName ?? plotted.location.label,
                    coordinate: plotted.displayCoordinate
                )
                .tag(plotted.location)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
    }
}

/// Separate view for the stats badge so it also skips recomputation on search keystrokes.
private struct MapStatsOverlay: View {
    let contacts: [Contact]
    let selectedTagIDs: Set<UUID>

    private var stats: (contactCount: Int, locationCount: Int) {
        let filterByTags = !selectedTagIDs.isEmpty
        var contactCount = 0
        var locationCount = 0

        for contact in contacts {
            if filterByTags {
                let contactTagIDs = Set((contact.tags ?? []).map(\.id))
                if selectedTagIDs.isDisjoint(with: contactTagIDs) { continue }
            }
            var hasLocation = false
            for loc in contact.locations ?? [] {
                guard loc.latitude != 0 || loc.longitude != 0 else { continue }
                locationCount += 1
                hasLocation = true
            }
            if hasLocation { contactCount += 1 }
        }

        return (contactCount, locationCount)
    }

    var body: some View {
        let s = stats
        if s.contactCount > 0 {
            Text("\(s.contactCount) contact\(s.contactCount == 1 ? "" : "s") \u{00B7} \(s.locationCount) location\(s.locationCount == 1 ? "" : "s")")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }
}
