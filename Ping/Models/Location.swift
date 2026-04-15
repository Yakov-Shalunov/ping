import SwiftData
import Foundation
import CoreLocation

@Model
final class Location {
    var id: UUID = UUID()
    var label: String = ""
    var address: String?
    var latitude: Double = 0
    var longitude: Double = 0
    var contact: Contact?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(label: String, address: String? = nil, latitude: Double = 0, longitude: Double = 0) {
        self.id = UUID()
        self.label = label
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }
}
