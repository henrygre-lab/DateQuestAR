import Foundation
import CoreLocation
import CoreHaptics
import Combine

// MARK: - LocationService

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var currentGeohash: String?
    @Published var isScanning = false

    private let locationManager = CLLocationManager()
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticPatternPlayer?

    // Geofence zones loaded from user prefs
    private var autoPauseZones: [GeoFenceZone] = []
    private var isPaused = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10                 // meters; update every 10m
        prepareHapticEngine()
    }

    // MARK: - Permissions

    func requestPermissions() {
        locationManager.requestAlwaysAuthorization()        // Required for background quest mode
    }

    // MARK: - Quest Scanning

    func startQuestScanning() {
        guard authorizationStatus == .authorizedAlways else {
            requestPermissions()
            return
        }
        isScanning = true
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        print("[LocationService] Quest scanning started.")
    }

    func stopQuestScanning() {
        isScanning = false
        locationManager.stopUpdatingLocation()
        stopHaptics()
        print("[LocationService] Quest scanning stopped.")
    }

    // MARK: - Auto-Pause Zones

    func configureAutoPauseZones(_ zones: [GeoFenceZone]) {
        autoPauseZones = zones
        locationManager.monitoredRegions.forEach { locationManager.stopMonitoring(for: $0) }
        for zone in zones where zone.isActive {
            guard let center = decodeGeohash(zone.geohash) else { continue }
            let region = CLCircularRegion(
                center: center,
                radius: zone.radiusMeters,
                identifier: zone.id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            locationManager.startMonitoring(for: region)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, !isPaused else { return }
        currentLocation = location
        currentGeohash = encodeGeohash(location.coordinate, precision: 7)
        broadcastLocationUpdate(location)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async { self.authorizationStatus = status }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if autoPauseZones.contains(where: { $0.id == region.identifier }) {
            isPaused = true
            stopHaptics()
            print("[LocationService] Auto-paused in zone: \(region.identifier)")
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if autoPauseZones.contains(where: { $0.id == region.identifier }) {
            isPaused = false
            print("[LocationService] Resumed from zone: \(region.identifier)")
        }
    }

    // MARK: - Proximity Broadcast

    private func broadcastLocationUpdate(_ location: CLLocation) {
        // In production: compare against nearby match locations from Firebase
        // For scaffold: post notification for MatchManager to handle
        NotificationCenter.default.post(
            name: .proximityUpdated,
            object: ProximityEvent(
                matchID: "stub_match_id",
                partnerUID: "stub_partner_uid",
                distanceMiles: 0.15,                        // TODO: Real distance calc
                hapticIntensity: hapticIntensity(for: 0.15),
                shouldRevealPhotos: false,
                timestamp: Date()
            )
        )
    }

    // MARK: - Haptics

    private func prepareHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            hapticEngine?.resetHandler = { [weak self] in
                try? self?.hapticEngine?.start()
            }
            hapticEngine?.stoppedHandler = { reason in
                print("[Haptics] Engine stopped: \(reason)")
            }
            try hapticEngine?.start()
        } catch {
            print("[Haptics] Engine init failed: \(error)")
        }
    }

    func playProximityHaptic(intensity: Float) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }

        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        let event = CHHapticEvent(eventType: .hapticContinuous,
                                  parameters: [intensityParam, sharpnessParam],
                                  relativeTime: 0, duration: 0.4)
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            hapticPlayer = try engine.makePlayer(with: pattern)
            try hapticPlayer?.start(atTime: 0)
        } catch {
            print("[Haptics] Playback failed: \(error)")
        }
    }

    func stopHaptics() {
        try? hapticPlayer?.stop(atTime: 0)
    }

    func hapticIntensity(for distanceMiles: Double) -> Float {
        // Ramp from 0.1 (0.25 mi) to 1.0 (0.0 mi)
        let clamped = min(max(distanceMiles, 0), 0.25)
        return Float(1.0 - (clamped / 0.25))
    }

    // MARK: - Geohash Utilities

    /// Encodes a coordinate to a geohash string for anonymized location storage.
    func encodeGeohash(_ coordinate: CLLocationCoordinate2D, precision: Int = 7) -> String {
        // TODO: Implement or import a geohash library (e.g., GeoFire)
        // Placeholder returns coordinate as string
        return "\(coordinate.latitude.rounded(toPlaces: 3)),\(coordinate.longitude.rounded(toPlaces: 3))"
    }

    /// Decodes a geohash back to a coordinate (used for geofence centers only, never shared raw).
    func decodeGeohash(_ geohash: String) -> CLLocationCoordinate2D? {
        // TODO: Implement geohash decoding
        return nil
    }
}

// MARK: - Double Extension

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
