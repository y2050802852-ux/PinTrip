import CoreLocation
import MapKit
import Observation

/// Wraps `MKLocalSearchCompleter` for as-you-type suggestions and
/// `MKLocalSearch` for resolving a suggestion into a concrete coordinate.
///
/// `MKLocalSearchCompleter` is preferred over third-party geocoders here:
/// it needs no API key, it supports autocomplete natively, and because the
/// map is rendered by MapKit the results are guaranteed to share the map's
/// coordinate system (no GCJ-02 / WGS-84 conversion needed).
@Observable
final class PlaceSearchService: NSObject, MKLocalSearchCompleterDelegate {
    var suggestions: [PlaceSuggestion] = []
    var errorMessage: String?

    private let completer: MKLocalSearchCompleter

    /// City name used to bias searches, applied as query text.
    ///
    /// Deliberately NOT applied as `MKLocalSearch.Request.region`: on macOS 26
    /// setting `region` makes every search fail with `MKErrorPlacemarkNotFound`
    /// (MKErrorDomain code 4, `MKErrorGEOError=-8`), even a region that matches
    /// the target exactly. Verified by reproduction. Biasing via query text
    /// achieves the same narrowing without triggering the failure.
    var biasCity: String? {
        didSet { completer.region = MKCoordinateRegion(.world) }
    }

    override init() {
        self.completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .query]
        completer.region = MKCoordinateRegion(.world)
    }

    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            completer.cancel()
            suggestions = []
            errorMessage = nil
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        completer.cancel()
        completer.queryFragment = ""
        suggestions = []
        errorMessage = nil
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        errorMessage = nil
        suggestions = completer.results.compactMap { PlaceSuggestion(completion: $0) }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
        errorMessage = error.localizedDescription
    }

    // MARK: - Resolve

    /// Resolves a suggestion into a coordinate via `MKLocalSearch`.
    ///
    /// `region` is intentionally left unset — see `biasCity`.
    func resolve(_ suggestion: PlaceSuggestion) async throws -> CLLocationCoordinate2D {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
            throw PlaceSearchError.noResult
        }
        return item.placemark.coordinate
    }

    /// Free-text search, used when the user presses Return without picking a suggestion.
    /// The destination city is prepended to narrow results, since `region` cannot be used.
    func search(_ text: String) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = biasedQuery(text)
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems
    }

    /// Prepends the destination city so results skew toward the plan's city.
    private func biasedQuery(_ text: String) -> String {
        guard let city = biasCity, !city.isEmpty, !text.isEmpty else { return text }
        // Avoid duplicating an explicit city prefix the user already typed.
        if text.contains(city) { return text }
        return "\(city) \(text)"
    }
}

struct PlaceSuggestion: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion

    init?(completion: MKLocalSearchCompletion) {
        guard !completion.title.isEmpty else { return nil }
        self.completion = completion
        self.title = completion.title
        self.subtitle = completion.subtitle
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(subtitle)
    }

    static func == (lhs: PlaceSuggestion, rhs: PlaceSuggestion) -> Bool {
        lhs.title == rhs.title && lhs.subtitle == rhs.subtitle
    }
}

enum PlaceSearchError: LocalizedError {
    case noResult

    var errorDescription: String? { "未找到该地点" }
}
