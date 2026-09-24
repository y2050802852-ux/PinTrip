import CoreLocation
import Observation

/// One-shot user location for the map's "locate me" button.
///
/// Authorization is handled EVENT-DRIVEN: `locationManagerDidChangeAuthorization`
/// resolves the pending request when the user answers the system prompt.
/// The previous implementation polled `authorizationStatus` for 3 seconds and
/// then called `requestLocation` regardless — if the prompt was still on
/// screen (or had been denied), locationd rejected the request with
/// kCLErrorDomain error 1 (kCLErrorDenied).
@MainActor
@Observable
final class UserLocationService: NSObject, CLLocationManagerDelegate {
    /// Last known position; also drives the map's user-dot availability.
    var currentCoordinate: CLLocationCoordinate2D?
    var isLocating = false
    /// True when the system denied location; the UI shows a Settings hint.
    var isDenied = false

    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Reflect an already-denied state from a previous session at init.
        isDenied = manager.authorizationStatus == .denied
    }

    func locate() async throws -> CLLocationCoordinate2D {
        guard pending == nil else {
            throw LocationError.inProgress
        }

        let status = manager.authorizationStatus
        guard status != .denied, status != .restricted else {
            isDenied = true
            throw LocationError.denied
        }

        isLocating = true
        defer { isLocating = false }

        // notDetermined → ask; the answer arrives via the delegate callback
        // and resumes the continuation from there.
        if status == .notDetermined {
            return try await withCheckedThrowingContinuation { c in
                pending = c
                awaitingAuthorization = true
                manager.requestWhenInUseAuthorization()
            }
        }

        return try await requestOnce()
    }

    private func requestOnce() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { c in
            pending = c
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            self.isDenied = (status == .denied || status == .restricted)
            // Resolve a pending authorization request: proceed or fail it.
            guard let c = self.pending, self.awaitingAuthorization else { return }
            self.awaitingAuthorization = false
            switch status {
            case .notDetermined:
                break // still deciding; keep waiting
            case .denied, .restricted:
                c.resume(throwing: LocationError.denied)
            default:
                // Authorized — chain into the actual location request.
                Task { @MainActor in
                    do {
                        let coordinate = try await self.requestOnce()
                        c.resume(returning: coordinate)
                    } catch {
                        c.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// True between requestWhenInUseAuthorization and the delegate callback.
    private var awaitingAuthorization = false

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.isLocating = false
            let coordinate = locations.first?.coordinate
            self.currentCoordinate = coordinate
            if let coordinate {
                self.pending?.resume(returning: coordinate)
            } else {
                self.pending?.resume(throwing: LocationError.unavailable)
            }
            self.pending = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isLocating = false
            self.pending?.resume(throwing: error)
            self.pending = nil
        }
    }
}

enum LocationError: LocalizedError {
    case denied
    case inProgress
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied:
            return "定位权限未开启。请在 系统设置 → 隐私与安全性 → 定位服务 中找到 PinTrip 并选择「允许」。"
        case .inProgress:
            return "正在处理上一次定位请求，请稍候。"
        case .unavailable:
            return "暂时无法获取位置，请稍后重试。"
        }
    }
}
