import CoreLocation
import Foundation
import SwiftData

/// A trip plan. Groups `Place`s and carries an optional destination city
/// used to bias searches and to set the map's initial camera.
@Model
final class Plan {
    var name: String
    var createdAt: Date

    /// Optional destination city the plan is centered on.
    var destinationName: String?
    var destinationLatitude: Double?
    var destinationLongitude: Double?

    /// Radius in meters used to bias `MKLocalSearch` toward this plan's city.
    var searchRadius: Double = 25_000

    /// Many-to-many: a place may belong to several plans.
    @Relationship(inverse: \Place.plans)
    var places: [Place] = []

    init(name: String, destinationName: String? = nil) {
        self.name = name
        self.createdAt = Date()
        self.destinationName = destinationName
    }

    var destinationCoordinate: CLLocationCoordinate2D? {
        guard let latitude = destinationLatitude,
              let longitude = destinationLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func setDestination(name: String, coordinate: CLLocationCoordinate2D, radius: Double = 25_000) {
        destinationName = name
        destinationLatitude = coordinate.latitude
        destinationLongitude = coordinate.longitude
        searchRadius = radius
    }

    /// Places sorted by their within-plan order, falling back to creation order.
    var orderedPlaces: [Place] {
        places.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
