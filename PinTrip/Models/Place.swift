import CoreLocation
import Foundation
import SwiftData
import SwiftUI

enum PlaceCategory: String, Codable, CaseIterable, Identifiable {
    case sight = "景点"
    case food = "餐饮"
    case lodging = "住宿"
    case transport = "交通"
    case other = "其他"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .sight: return .blue
        case .food: return .orange
        case .lodging: return .green
        case .transport: return .gray
        case .other: return .purple
        }
    }

    var symbolName: String {
        switch self {
        case .sight: return "binoculars.fill"
        case .food: return "fork.knife"
        case .lodging: return "bed.double.fill"
        case .transport: return "tram.fill"
        case .other: return "mappin"
        }
    }
}

@Model
final class Place {
    var name: String
    var latitude: Double
    var longitude: Double

    /// Stable identity for backup export/import matching; see `Plan.backupID`.
    var backupID: UUID = UUID()

    var notes: String = ""
    /// Raw value of `PlaceCategory`. Stored as a String so SwiftData needs no custom transformer.
    var categoryRaw: String = PlaceCategory.sight.rawValue

    /// Position within a plan. See note in README: with many-to-many sharing
    /// this value is shared across every plan that contains the place.
    var sortOrder: Int = 0
    var day: Int = 1

    var rating: Int = 0
    var visited: Bool = false

    var linkURL: String = ""
    /// Reserved for V2. Kept in the schema now so no migration is needed later.
    var photoPath: String = ""

    /// The stored `linkURL` when it parses as an absolute http(s) URL, else nil.
    /// Guards against rendering a `Link` for partially typed input.
    var link: String? {
        guard !linkURL.isEmpty,
              let url = URL(string: linkURL),
              let scheme = url.scheme,
              scheme == "http" || scheme == "https"
        else { return nil }
        return linkURL
    }

    var createdAt: Date = Date()

    /// Inverse side of `Plan.places`; SwiftData resolves the pairing via the
    /// `@Relationship(inverse:)` declared on `Plan`. Many-to-many: a place may
    /// belong to several plans.
    var plans: [Plan] = []

    init(
        name: String,
        coordinate: CLLocationCoordinate2D,
        category: PlaceCategory = .sight
    ) {
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.categoryRaw = category.rawValue
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var category: PlaceCategory {
        get { PlaceCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}
