import CoreLocation
import Observation

/// One-shot user location for the map's "locate me" button.
///
/// Authorization is event-driven (`locationManagerDidChangeAuthorization`
/// resolves the pending request). Position acquisition uses
/// `startUpdatingLocation` with a timeout instead of `requestLocation`:
/// single-shot requests fail hard on transient Wi-Fi-positioning errors
/// (kCLErrorLocationUnknown), while continuous updates deliver the first
/// fix as soon as one becomes available.
@MainActor
@Observable
final class UserLocationService: NSObject, CLLocationManagerDelegate {
    var currentCoordinate: CLLocationCoordinate2D?
    var isLocating = false
    /// True when the system denied location; the UI shows a Settings hint.
    var isDenied = false
    /// Human-readable reason when a locate attempt failed.
    var lastError: String?

    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var awaitingAuthorization = false
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Reflect an already-denied state from a previous session at init.
        isDenied = manager.authorizationStatus == .denied
    }

    func locate() async throws -> CLLocationCoordinate2D {
        guard pending == nil else { throw LocationError.inProgress }

        let status = manager.authorizationStatus
        guard status != .denied, status != .restricted else {
            isDenied = true
            throw LocationError.denied
        }

        isLocating = true
        lastError = nil

        // Ask for authorization first when needed; the answer arrives
        // through the delegate and re-enters this flow.
        if status == .notDetermined {
            return try await withCheckedThrowingContinuation { c in
                pending = c
                awaitingAuthorization = true
                manager.requestWhenInUseAuthorization()
            }
        }

        return try await acquireWithTimeout()
    }

    /// Continuous updates with a hard timeout; first fix wins.
    private func acquireWithTimeout() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { c in
            pending = c
            manager.startUpdatingLocation()

            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await MainActor.run {
                    guard let self, self.pending != nil else { return }
                    self.finish(.failure(LocationError.timeout))
                }
            }
        }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        manager.stopUpdatingLocation()
        isLocating = false
        switch result {
        case .success(let coordinate):
            currentCoordinate = coordinate
            pending?.resume(returning: coordinate)
        case .failure(let error):
            lastError = error.localizedDescription
            pending?.resume(throwing: error)
        }
        pending = nil
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            self.isDenied = (status == .denied || status == .restricted)
            guard self.awaitingAuthorization, let c = self.pending else { return }
            self.awaitingAuthorization = false
            switch status {
            case .notDetermined:
                break // still deciding; keep waiting
            case .denied, .restricted:
                self.finish(.failure(LocationError.denied))
                _ = c // resolved via finish()
            default:
                Task { @MainActor in
                    do {
                        let coordinate = try await self.acquireWithTimeout()
                        c.resume(returning: coordinate)
                    } catch {
                        c.resume(throwing: error)
                    }
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard self.pending != nil, let location = locations.first else { return }
            self.finish(.success(location.coordinate))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // Transient failures (kCLErrorLocationUnknown) are not fatal under
            // continuous updates — keep waiting for the next event or timeout.
            if (error as? CLError)?.code == .locationUnknown { return }
            guard self.pending != nil else { return }
            self.finish(.failure(error))
        }
    }
}

enum LocationError: LocalizedError {
    case denied
    case inProgress
    case timeout
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied:
            return "定位权限未开启。请在 系统设置 → 隐私与安全性 → 定位服务 中找到 PinTrip 并选择「允许」。"
        case .inProgress:
            return "正在处理上一次定位请求，请稍候。"
        case .timeout:
            return "定位超时：无法获取当前位置。请确认 Mac 已联网，且定位服务总开关已打开（系统设置 → 隐私与安全性 → 定位服务）。"
        case .unavailable:
            return "暂时无法获取位置，请稍后重试。"
        }
    }
}
