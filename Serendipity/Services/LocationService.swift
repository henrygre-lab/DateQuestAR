// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] No raw coordinates stored — only geohash precision 7 leaves this file, and
//     the campus / destination check-in sends a geohash, never a coordinate
// [x] User auto-pause zones respected (home, work, custom)
// [x] Campus geofence auto-pause — off campus and outside every live Spring Break
//     fence, communityScope is .none and Quest Mode stops. Fail-closed: the scope
//     starts at .none and only a positive containment test moves it off.
// [x] Campus and destination geofences come from backend documents; there is no
//     client-authored polygon and no client-authored window
// [x] Cross-school visibility requires a server confirmation round-trip
//     (confirmDestinationPresence) — detecting the fence locally is not enough
// [x] Leaving a destination clears presence server-side, so no cross-school radar
//     survives the trip home
// [x] No place name is derived or published here — the scope carries a schoolId or
//     the destination's own server-supplied label, never a neighbourhood or venue
// [x] No PII logged — region identifiers and scope transitions only

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

    // MARK: - Community Scope

    /// Which pool the device is currently allowed to see.
    ///
    /// Starts at `.none` and stays there until a containment test says otherwise.
    /// Everything downstream — the nearby query, the match path, the icebreaker —
    /// reads this, so an unknown location means an empty pool rather than an
    /// unscoped one.
    @Published private(set) var communityScope: CommunityScope = .none

    /// The user's own campus, from `schools/{schoolId}`.
    private var campus: (schoolId: String, geofence: CampusGeofence)?

    /// Live-window destinations, from `spring_break_destinations`.
    private var springBreakDestinations: [SpringBreakDestination] = []

    /// Destination whose fence we are currently inside and the server has
    /// confirmed. Nil unless both are true.
    private var confirmedDestination: SpringBreakDestination?

    private static let campusRegionIdentifier = "serendipity.campus"
    private static let destinationRegionPrefix = "serendipity.destination."

    /// Quest radius in miles for the current scope. Tightens after dusk inside a
    /// Spring Break destination.
    var currentQuestRadiusMiles: Double {
        guard let destination = confirmedDestination, destination.isAfterDusk() else {
            return 0.25
        }
        return destination.duskRadiusMiles
    }

    /// True when the UI should default to Squad Radar: after dusk at a
    /// destination, where people arrive in groups and should stay in them.
    var prefersSquadRadar: Bool {
        confirmedDestination?.isAfterDusk() ?? false
    }

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
        Log.location.debug("Quest scanning started.")
    }

    func stopQuestScanning() {
        isScanning = false
        locationManager.stopUpdatingLocation()
        stopHaptics()
        Log.location.debug("Quest scanning stopped.")
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

    // MARK: - Campus Geofence

    /// Arms the user's campus boundary from their school document.
    ///
    /// The centre arrives as a geohash and is decoded here purely to build a
    /// `CLCircularRegion`. It is never written back, never published, and never
    /// rendered — DESIGN_SYSTEM.md §8 allows the school's *name*, not its
    /// coordinates.
    func configureCampus(schoolId: String, geofence: CampusGeofence) {
        campus = (schoolId, geofence)

        locationManager.monitoredRegions
            .filter { $0.identifier == Self.campusRegionIdentifier }
            .forEach { locationManager.stopMonitoring(for: $0) }

        guard let center = decodeGeohash(geofence.centerGeohash) else {
            Log.location.error("Campus geofence could not be decoded")
            return
        }

        let region = CLCircularRegion(center: center,
                                      radius: geofence.radiusMeters,
                                      identifier: Self.campusRegionIdentifier)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager.startMonitoring(for: region)

        // Region monitoring only fires on a crossing. Evaluate immediately so a
        // user who launches the app already on campus is not stuck at .none.
        reevaluateScope()
    }

    /// Arms the live Spring Break destination fences.
    ///
    /// Only destinations whose server-dated window is currently live are armed.
    /// A destination out of window is not a place the app knows about.
    func configureSpringBreakDestinations(_ destinations: [SpringBreakDestination]) {
        springBreakDestinations = destinations.filter { $0.isLive() }

        locationManager.monitoredRegions
            .filter { $0.identifier.hasPrefix(Self.destinationRegionPrefix) }
            .forEach { locationManager.stopMonitoring(for: $0) }

        for destination in springBreakDestinations {
            guard let id = destination.id,
                  let center = decodeGeohash(destination.centerGeohash) else { continue }
            let region = CLCircularRegion(center: center,
                                          radius: destination.radiusMeters,
                                          identifier: Self.destinationRegionPrefix + id)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            locationManager.startMonitoring(for: region)
        }

        reevaluateScope()
    }

    // MARK: - Scope Evaluation

    /// Recomputes `communityScope` from the current location.
    ///
    /// Order matters. Campus wins over a destination fence: a student standing on
    /// their own campus belongs to their own community, whatever else overlaps.
    /// Everything else is `.none`, which pauses Quest Mode.
    private func reevaluateScope() {
        guard let location = currentLocation else {
            setScope(.none)
            return
        }

        if let campus, containsLocation(location, geohash: campus.geofence.centerGeohash,
                                        radius: campus.geofence.radiusMeters) {
            if confirmedDestination != nil { Task { await releaseDestination() } }
            setScope(.campus(schoolId: campus.schoolId))
            return
        }

        if let destination = springBreakDestinations.first(where: {
            $0.isLive() && containsLocation(location,
                                            geohash: $0.centerGeohash,
                                            radius: $0.radiusMeters)
        }) {
            Task { await claimDestination(destination) }
            return
        }

        if confirmedDestination != nil { Task { await releaseDestination() } }
        setScope(.none)
    }

    private func containsLocation(_ location: CLLocation,
                                  geohash: String,
                                  radius: Double) -> Bool {
        guard let center = decodeGeohash(geohash) else { return false }
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return location.distance(from: centerLocation) <= radius
    }

    /// Asks the backend to confirm presence, and only then widens the pool.
    ///
    /// Being inside the fence is necessary but not sufficient: the cross-school
    /// pool opens on a custom claim that only `confirmDestinationPresence` can
    /// issue, after it re-checks the fence and the window against its own copies.
    /// A tampered client that skips this call gets a claimless token and reads
    /// nothing.
    @MainActor
    private func claimDestination(_ destination: SpringBreakDestination) async {
        guard let id = destination.id else { return }
        guard confirmedDestination?.id != id else { return }
        guard let geohash = currentGeohash else { return }

        let label = await SchoolGateManager.shared
            .confirmDestinationPresence(destinationId: id, geohash: geohash)

        guard let label else {
            // Server said no. Stay paused rather than falling back to campus —
            // the user is demonstrably not on campus either.
            confirmedDestination = nil
            setScope(.none)
            return
        }

        confirmedDestination = destination
        setScope(.springBreak(destinationId: id, displayLabel: label))
    }

    /// Drops destination presence on the server and locally.
    @MainActor
    private func releaseDestination() async {
        confirmedDestination = nil
        await SchoolGateManager.shared.clearDestinationPresence()
    }

    private func setScope(_ scope: CommunityScope) {
        guard communityScope != scope else { return }
        communityScope = scope
        // Off campus and outside every live fence means Quest Mode has nothing
        // to scan for. This is the auto-pause the product rules require.
        isPaused = (scope == .none)
        if isPaused { stopHaptics() }
        Log.location.debug("Community scope changed")
        Task { await MatchManager.shared.communityScopeChanged(to: scope) }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        currentGeohash = encodeGeohash(location.coordinate, precision: 7)

        // Scope is evaluated even while paused — that is how the app notices the
        // user walking back onto campus.
        reevaluateScope()

        guard !isPaused else { return }
        Task {
            await MatchManager.shared.refreshNearbyUsers()
        }
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
            // A user pause zone wins over everything, including being on campus.
            // Home is home.
            isPaused = true
            stopHaptics()
            Log.location.debug("Auto-paused in a user zone")
            return
        }
        reevaluateScope()
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if autoPauseZones.contains(where: { $0.id == region.identifier }) {
            isPaused = false
            Log.location.debug("Resumed from a user zone")
            reevaluateScope()
            return
        }
        reevaluateScope()
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
                Log.haptics.debug("Engine stopped: \(reason)")
            }
            try hapticEngine?.start()
        } catch {
            Log.haptics.error("Engine init failed: \(error)")
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
            Log.haptics.error("Playback failed: \(error)")
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
