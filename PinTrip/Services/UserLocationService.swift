import CoreLocation
import Observation

/// One-shot user location for the map's "locate me" button.
///
/// Requests when-in-use authorization on first press, then a single
/// `requestLocation` per press — no continuous tracking, this app pins
/// places, it doesn't navigate.
@MainActor
@Observable
final class UserLocationService: NSObject, CLLocationManagerDelegate {
    var currentCoordinate: CLLocationCoordinate2D?
    var isLocating = false
    var errorMessage: String?

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func locate() async throws -> CLLocationCoordinate2D {
        errorMessage = nil
        isLocating = true
        defer { isLocating = false }

        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // Wait briefly for the user to answer the system prompt.
            for _ in 0..<30 where manager.authorizationStatus == .notDetermined {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        guard manager.authorizationStatus != .denied, manager.authorizationStatus != .restricted else {
            throw LocationError.denied
        }

        return try await withCheckedThrowingContinuation { c in
            continuation = c
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            let coordinate = locations.first?.coordinate
            currentCoordinate = coordinate
            continuation?.resume(returning: coordinate ?? CLLocationCoordinate2D())
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = error.localizedDescription
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

enum LocationError: LocalizedError {
    case denied

    var errorDescription: String? {
        "定位权限被拒绝。请在 系统设置 → 隐私与安全性 → 定位服务 中允许 PinTrip 使用定位。"
    }
}
