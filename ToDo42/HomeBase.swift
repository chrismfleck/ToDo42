import Foundation
import Observation
import CoreLocation

@Observable
@MainActor
final class HomeBase: NSObject, CLLocationManagerDelegate {
    static let shared = HomeBase()

    var latitude: Double?
    var longitude: Double?
    var label = ""
    var isSetting = false
    var statusMessage = ""

    private let latKey = "todo42.homeLatitude"
    private let lonKey = "todo42.homeLongitude"
    private let labelKey = "todo42.homeLabel"
    private let defaults = UserDefaults.standard
    private let manager = CLLocationManager()
    private var locationWaiter: CheckedContinuation<CLLocation, Error>?
    private var authWaiter: CheckedContinuation<Void, Error>?

    var isSet: Bool { latitude != nil && longitude != nil }

    var location: CLLocation? {
        guard let latitude, let longitude else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return isSet ? "Home set" : "Not set"
    }

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if defaults.object(forKey: latKey) != nil {
            latitude = defaults.double(forKey: latKey)
            longitude = defaults.double(forKey: lonKey)
            label = defaults.string(forKey: labelKey) ?? ""
        }
    }

    func miles(to latitude: Double, longitude: Double) -> Double? {
        guard let origin = location else { return nil }
        return ItemPlace.miles(from: origin, to: latitude, longitude: longitude)
    }

    func setFromCurrentLocation() async {
        isSetting = true
        statusMessage = ""
        defer { isSetting = false }
        do {
            try await waitForAuthorization()
            let fix = try await requestFix()
            let marks = try? await CLGeocoder().reverseGeocodeLocation(fix)
            latitude = fix.coordinate.latitude
            longitude = fix.coordinate.longitude
            label = ItemPlace.placeLabel(marks?.first) ?? "Home"
            defaults.set(latitude, forKey: latKey)
            defaults.set(longitude, forKey: lonKey)
            defaults.set(label, forKey: labelKey)
            statusMessage = "Home set to \(label)."
        } catch {
            statusMessage = Self.message(for: error)
        }
    }

    private func waitForAuthorization() async throws {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return
        case .denied, .restricted:
            throw HomeBaseError.denied
        case .notDetermined:
            try await withCheckedThrowingContinuation { continuation in
                authWaiter?.resume(throwing: HomeBaseError.busy)
                authWaiter = continuation
                manager.requestWhenInUseAuthorization()
            }
        @unknown default:
            throw HomeBaseError.denied
        }
    }

    private func requestFix() async throws -> CLLocation {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            throw HomeBaseError.denied
        }
        if let cached = manager.location, Date().timeIntervalSince(cached.timestamp) < 120 {
            return cached
        }
        return try await withCheckedThrowingContinuation { continuation in
            locationWaiter?.resume(throwing: HomeBaseError.busy)
            locationWaiter = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                self.authWaiter?.resume()
                self.authWaiter = nil
            case .denied, .restricted:
                self.authWaiter?.resume(throwing: HomeBaseError.denied)
                self.authWaiter = nil
                self.failWaiter(HomeBaseError.denied)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.last {
                self.locationWaiter?.resume(returning: location)
                self.locationWaiter = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.failWaiter(error)
        }
    }

    private func failWaiter(_ error: Error) {
        locationWaiter?.resume(throwing: error)
        locationWaiter = nil
    }

    private static func message(for error: Error) -> String {
        if let home = error as? HomeBaseError { return home.localizedDescription }
        if let cl = error as? CLError, cl.code == .denied {
            return HomeBaseError.denied.localizedDescription
        }
        return "Couldn't get this phone’s location. Try again at home."
    }
}

enum HomeBaseError: LocalizedError {
    case denied
    case busy

    var errorDescription: String? {
        switch self {
        case .denied:
            "Turn on Location for Save 4 Two in Settings, then tap Set home."
        case .busy:
            "Still setting home. Try again in a moment."
        }
    }
}
