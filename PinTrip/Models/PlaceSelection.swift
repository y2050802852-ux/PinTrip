import MapKit
import SwiftData
// MapSelectable/MapFeature live in the underscored MapKit-SwiftUI framework,
// re-exported through MapKit's Swift overlay.
import _MapKit_SwiftUI

/// Selection value for SwiftUI `Map(selection:)`.
///
/// `Map` requires its selection value to conform to `MapSelectable` so it
/// can reconcile marker taps with empty-map taps; `PersistentIdentifier`
/// doesn't conform, so the identifier is wrapped. When the user taps empty
/// map space, `Map` sets the binding to `nil`, which the app reads as
/// "close the place inspector".
struct PlaceSelection: MapSelectable, Hashable {
    let placeID: PersistentIdentifier?

    var feature: MapFeature? { nil }

    init(_ placeID: PersistentIdentifier?) {
        self.placeID = placeID
    }

    init(_ feature: MapFeature?) {
        // Feature taps carry no place identity; treat as deselection.
        self.placeID = nil
    }
}
