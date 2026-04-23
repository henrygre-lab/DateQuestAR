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
    private var pendingQuestStart = false

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
            pendingQuestStart = true
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
        if status == .authorizedAlways && pendingQuestStart {
            pendingQuestStart = false
            startQuestScanning()
        }
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
        // Real proximity events are posted by ProximityService when UWB/BLE detects a match.
        // LocationService only updates currentLocation and currentGeohash.
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

    private static let geohashBase32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// Encodes a coordinate to a geohash string for anonymized location storage.
    func encodeGeohash(_ coordinate: CLLocationCoordinate2D, precision: Int = 7) -> String {
        let base32 = Self.geohashBase32
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var isLon = true
        var bits = 0
        var charIndex = 0
        var hash = ""

        while hash.count < precision {
            let mid: Double
            if isLon {
                mid = (lonRange.0 + lonRange.1) / 2
                if coordinate.longitude >= mid {
                    charIndex = charIndex * 2 + 1
                    lonRange.0 = mid
                } else {
                    charIndex = charIndex * 2
                    lonRange.1 = mid
                }
            } else {
                mid = (latRange.0 + latRange.1) / 2
                if coordinate.latitude >= mid {
                    charIndex = charIndex * 2 + 1
                    latRange.0 = mid
                } else {
                    charIndex = charIndex * 2
                    latRange.1 = mid
                }
            }
            isLon.toggle()
            bits += 1

            if bits == 5 {
                hash.append(base32[charIndex])
                bits = 0
                charIndex = 0
            }
        }
        return hash
    }

    /// Decodes a geohash back to a coordinate (used for geofence centers only, never shared raw).
    func decodeGeohash(_ geohash: String) -> CLLocationCoordinate2D? {
        let base32 = Self.geohashBase32
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var isLon = true

        for char in geohash.lowercased() {
            guard let index = base32.firstIndex(of: char) else { return nil }
            let value = base32.distance(from: base32.startIndex, to: index)

            for i in stride(from: 4, through: 0, by: -1) {
                let bit = (value >> i) & 1
                if isLon {
                    let mid = (lonRange.0 + lonRange.1) / 2
                    if bit == 1 { lonRange.0 = mid } else { lonRange.1 = mid }
                } else {
                    let mid = (latRange.0 + latRange.1) / 2
                    if bit == 1 { latRange.0 = mid } else { latRange.1 = mid }
                }
                isLon.toggle()
            }
        }

        let latitude = (latRange.0 + latRange.1) / 2
        let longitude = (lonRange.0 + lonRange.1) / 2
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
