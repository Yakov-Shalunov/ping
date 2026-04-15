import SwiftUI
import SwiftData
import MapKit

struct ContactMapView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.firstName) private var contacts: [Contact]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var searchText = ""
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var selectedLocation: Location?
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var showingLogCheckIn: Contact?

    private var visibleLocations: [Location] {
        var locs = contacts.flatMap { $0.locations ?? [] }

        // Filter out locations with no coordinates (not yet geocoded)
        locs = locs.filter { $0.latitude != 0 || $0.longitude != 0 }

        if !selectedTagIDs.isEmpty {
            locs = locs.filter { loc in
                guard let contact = loc.contact else { return false }
                let contactTagIDs = Set((contact.tags ?? []).map(\.id))
                return !selectedTagIDs.isDisjoint(with: contactTagIDs)
            }
        }

        return locs
    }

    private var uniqueContactCount: Int {
        Set(visibleLocations.compactMap { $0.contact?.id }).count
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $mapPosition, selection: $selectedLocation) {
                    ForEach(visibleLocations) { location in
                        Marker(
                            location.contact?.displayName ?? location.label,
                            coordinate: location.coordinate
                        )
                        .tag(location)
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }

                VStack(spacing: 8) {
                    searchBar
                    if !allTags.isEmpty {
                        tagFilterBar
                    }
                    if uniqueContactCount > 0 {
                        Text("\(uniqueContactCount) contact\(uniqueContactCount == 1 ? "" : "s") \u{00B7} \(visibleLocations.count) location\(visibleLocations.count == 1 ? "" : "s")")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
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
