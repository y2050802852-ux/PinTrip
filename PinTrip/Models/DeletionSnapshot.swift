import CoreLocation
import Foundation
import SwiftData

/// Full value snapshot of a `Place`, taken before deletion so Undo can
/// rebuild it. SwiftData objects cannot survive their own deletion, and
/// SwiftData has no built-in undo manager, so the values are copied out.
struct PlaceSnapshot: Identifiable {
    let id: PersistentIdentifier
    let name: String
    let latitude: Double
    let longitude: Double
    let notes: String
    let categoryRaw: String
    let sortOrder: Int
    let day: Int
    let rating: Int
    let visited: Bool
    let linkURL: String
    let photoPath: String
    let createdAt: Date

    init(place: Place) {
        self.id = place.id
        self.name = place.name
        self.latitude = place.latitude
        self.longitude = place.longitude
        self.notes = place.notes
        self.categoryRaw = place.categoryRaw
        self.sortOrder = place.sortOrder
        self.day = place.day
        self.rating = place.rating
        self.visited = place.visited
        self.linkURL = place.linkURL
        self.photoPath = place.photoPath
        self.createdAt = place.createdAt
    }

    func makePlace() -> Place {
        let place = Place(
            name: name,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )
        place.notes = notes
        place.categoryRaw = categoryRaw
        place.sortOrder = sortOrder
        place.day = day
        place.rating = rating
        place.visited = visited
        place.linkURL = linkURL
        place.photoPath = photoPath
        place.createdAt = createdAt
        return place
    }
}

/// Everything needed to rebuild a deleted plan and the places it owned.
struct PlanDeletion {
    let name: String
    let createdAt: Date
    let destinationName: String?
    let destinationLatitude: Double?
    let destinationLongitude: Double?
    let searchRadius: Double
    let startDate: Date?
    let endDate: Date?
    let places: [PlaceSnapshot]

    init(plan: Plan) {
        self.name = plan.name
        self.createdAt = plan.createdAt
        self.destinationName = plan.destinationName
        self.destinationLatitude = plan.destinationLatitude
        self.destinationLongitude = plan.destinationLongitude
        self.searchRadius = plan.searchRadius
        self.startDate = plan.startDate
        self.endDate = plan.endDate
        self.places = plan.places.map { PlaceSnapshot(place: $0) }
    }

    var placeCount: Int { places.count }
}
