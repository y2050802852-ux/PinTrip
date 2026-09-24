import CoreLocation
import Foundation

/// A candidate location that has been resolved but not yet saved.
/// Lets the map focus on it and the user confirm before it enters the plan.
struct PlacePreview: Identifiable, Equatable {
    enum Source: Equatable {
        case search
        /// Created by right-clicking the map; name is filled in by the user.
        case manualDrop
    }

    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let source: Source

    /// True when the name still needs to be typed (right-click drops).
    var needsName: Bool { source == .manualDrop || name.isEmpty }

    /// `CLLocationCoordinate2D` is not Equatable, so compare by components.
    static func == (lhs: PlacePreview, rhs: PlacePreview) -> Bool {
        lhs.name == rhs.name
            && lhs.subtitle == rhs.subtitle
            && lhs.source == rhs.source
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}
