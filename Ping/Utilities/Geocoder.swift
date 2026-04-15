import Foundation
import CoreLocation
import SwiftData

/// Geocodes locations that have an address string but no coordinates.
/// Rate-limited to avoid hitting Apple's geocoding limits.
@MainActor
final class LocationGeocoder {
    private let geocoder = CLGeocoder()

    /// Geocode all locations missing coordinates in the given model context.
    func geocodeMissingLocations(in context: ModelContext) async {
        let descriptor = FetchDescriptor<Location>()
        guard let locations = try? context.fetch(descriptor) else { return }

        let needsGeocoding = locations.filter { loc in
            loc.latitude == 0 && loc.longitude == 0 && loc.address != nil && !loc.address!.isEmpty
        }

        for location in needsGeocoding {
            guard let address = location.address else { continue }
            do {
                let placemarks = try await geocoder.geocodeAddressString(address)
                if let coord = placemarks.first?.location?.coordinate {
                    location.latitude = coord.latitude
                    location.longitude = coord.longitude
                }
            } catch {
                // Skip failures — user can fix manually in Tidy Up
            }
            // Rate limit: Apple recommends no more than one geocode per second
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
