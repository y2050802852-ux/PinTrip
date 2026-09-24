import CoreLocation
import Foundation
import SwiftData

/// A trip plan. Groups `Place`s and carries an optional destination city
/// used to bias searches and to set the map's initial camera.
@Model
final class Plan {
    var name: String
    var createdAt: Date

    /// Stable identity for backup export/import matching. New records get a
    /// fresh UUID; records restored from a backup reuse the stored one so a
    /// re-import can match them instead of duplicating.
    var backupID: UUID = UUID()

    /// Optional destination city the plan is centered on.
    var destinationName: String?
    var destinationLatitude: Double?
    var destinationLongitude: Double?

    /// Itinerary window. Days are derived from these, not stored as entities,
    /// so changing the range does not require inserting/removing Day objects.
    /// A plan without dates (nil) is treated as a single undated day.
    var startDate: Date?
    var endDate: Date?

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

    /// Number of days in the itinerary; 1 when no dates are set.
    var dayCount: Int {
        guard let start = startDate, let end = endDate else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: startOfDay(start), to: startOfDay(end)).day ?? 0
        return max(1, days + 1)
    }

    /// Calendar date for a 0-based day index. Returns nil when undated.
    func date(forDayIndex index: Int) -> Date? {
        guard let start = startDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: index, to: startOfDay(start))
    }

    /// Day indices are 1-based in the UI and in `Place.day`.
    var dayNumbers: [Int] { Array(1...dayCount) }

    /// Clamps a day number into the valid range. Used when the date range
    /// shrinks so places never end up on a day that no longer exists.
    func clampedDay(_ day: Int) -> Int {
        min(max(day, 1), dayCount)
    }

    /// Short human-readable range for list subtitles.
    var dateRangeText: String? {
        guard let startDate, let endDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return "\(formatter.string(from: startDate))–\(formatter.string(from: endDate)) · \(dayCount) 天"
    }

    private func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
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
