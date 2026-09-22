import CoreLocation
import Foundation

/// Equatable wrapper for `CLLocationCoordinate2D` so it can be used in
/// SwiftUI `onChange` and ` Equatable` contexts (the raw struct is neither
/// Sendable-friendly nor Equatable in the way SwiftUI modifiers require).
struct MapCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
