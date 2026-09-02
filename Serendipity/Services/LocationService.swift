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
// [x] Cross-school visibility requires a server confirmation round-trip —
//     confirmDestinationPresence for a Spring Break fence, confirmCampusPresence
//     for another school's campus. Detecting a fence locally is never enough.
// [x] Visiting presence follows the same shape as destination presence: an
//     expiring claim, a 15-minute refresh, and an explicit paused state. It is
//     never allowed to lapse silently.
// [x] Leaving a destination clears presence server-side, so no cross-school radar
//     survives the trip home
// [x] The sbDest claim is short-lived and is re-confirmed every 15 minutes while
//     Quest Mode is on and the device is still inside the destination fence.
//     Each refresh is the same server round-trip that issued the claim — the
//     backend re-checks the fence and the dated window, so a refresh cannot
//     extend presence the user no longer has.
// [x] The cross-school pool never lapses silently. If a refresh fails, the window
//     closes, the user leaves the fence, or Quest Mode is switched off, presence
//     is released server-side and springBreakStatus becomes .paused, which the UI
//     surfaces. Falling back to same-school without saying so would leave someone
//     believing they were still in the multi-school pool.
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

    /// Every allowlisted campus, so a student can Quest on one that is not their
    /// own — the Big Game rule.
    ///
    /// Only the home campus gets a monitored `CLCircularRegion`: iOS caps an app
    /// at 20 regions, and a national school list would blow that on its own.
    /// Visiting campuses are detected by containment on location updates, which
    /// is exactly when it matters — Quest Mode is scanning, so updates are
    /// flowing. The trade-off is that walking onto another campus with the app
    /// asleep is noticed on the next update rather than instantly.
    private var allCampuses: [School] = []

    /// The campus currently being visited, once the server has confirmed it.
    private var confirmedVisitingCampus: School?

    /// Whether the device is confirmed on a campus that is not the user's own,
    /// and if not, why it stopped.
    @Published private(set) var visitingCampusStatus: VisitingCampusStatus = .inactive

    /// Local hour after which a visiting campus takes the night posture.
    ///
    /// A constant rather than a per-school field: `schools/{id}` has no dusk hour
    /// and adding one would need every school document reseeded. Matches the
    /// Spring Break destinations' own default.
    private static let visitingDuskLocalHour = 20

    /// Tightened Quest radius after dusk while visiting, in miles.
    private static let visitingDuskRadiusMiles = 0.1

    private var campusRefreshTask: Task<Void, Never>?
    private var suppressCampusClaims = false

    /// Live-window destinations, from `spring_break_destinations`.
    private var springBreakDestinations: [SpringBreakDestination] = []

    /// Whether the cross-school Spring Break pool is currently open, and if not,
    /// why. Published separately from `communityScope` on purpose: the scope
    /// decides who you can see, and this decides what the UI tells you about it.
    /// Collapsing them would mean either a fourth scope case that
    /// `CommunityGate` would have to interpret, or a silent fallback.
    @Published private(set) var springBreakStatus: SpringBreakStatus = .inactive

    /// Destination whose fence we are currently inside and the server has
    /// confirmed. Nil unless both are true.
    private var confirmedDestination: SpringBreakDestination?

    /// Server-confirmed presence is re-checked on this cadence, comfortably
    /// inside the backend's 45-minute claim TTL so a slow round-trip or one
    /// missed tick does not lapse the pool.
    private static let destinationRefreshSeconds: TimeInterval = 15 * 60

    private var destinationRefreshTask: Task<Void, Never>?

    /// Set when Spring Break presence is paused, to stop `reevaluateScope` from
    /// immediately re-claiming the same fence and looping. Cleared when the user
    /// actually leaves the destination region, or when Quest Mode restarts —
    /// both of which are real signals that a retry is worth making.
    private var suppressDestinationClaims = false

    private static let campusRegionIdentifier = "serendipity.campus"
    private static let destinationRegionPrefix = "serendipity.destination."

    /// Quest radius in miles for the current scope. Tightens after dusk inside a
    /// Spring Break destination.
    var currentQuestRadiusMiles: Double {
        if let destination = confirmedDestination, destination.isAfterDusk() {
            return destination.duskRadiusMiles
        }
        if isVisitingAfterDusk { return Self.visitingDuskRadiusMiles }
        return 0.25
    }

    /// True when the UI should default to Squad Radar.
    ///
    /// After dusk at a Spring Break destination, and after dusk on a campus that
    /// is not your own. Both are the same situation: you are somewhere you do
    /// not know, at night, among people you have never seen before.
    var prefersSquadRadar: Bool {
        (confirmedDestination?.isAfterDusk() ?? false) || isVisitingAfterDusk
    }

    /// Whether the user is on someone else's campus after dark.
    private var isVisitingAfterDusk: Bool {
        guard visitingCampusStatus.isActive else { return false }
        return Calendar.current.component(.hour, from: Date()) >= Self.visitingDuskLocalHour
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

        // Quest Mode coming back on is a real signal that a retry is worth
        // making, so a previous pause stops suppressing claims here.
        suppressDestinationClaims = false
        suppressCampusClaims = false
        reevaluateScope()

        Log.location.debug("Quest scanning started.")
    }

    func stopQuestScanning() {
        isScanning = false
        locationManager.stopUpdatingLocation()
        stopHaptics()

        // Presence is only meaningful while scanning. Releasing it here rather
        // than letting the claim age out means the cross-school pool closes when
        // the user stops looking, not 45 minutes later.
        if confirmedDestination != nil {
            Task { @MainActor in await pauseSpringBreak(.questModeOff) }
        } else {
            stopDestinationRefresh()
        }

        if confirmedVisitingCampus != nil {
            Task { @MainActor in await pauseVisitingCampus(.questModeOff) }
        } else {
            stopCampusRefresh()
        }

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

    /// Records every allowlisted campus so a student can Quest on one that is
    /// not their own.
    ///
    /// No regions are armed for these — see `allCampuses` for why. Containment is
    /// evaluated on location updates instead.
    func configureVisitableCampuses(_ schools: [School]) {
        allCampuses = schools.filter { $0.isActive && $0.id != nil }
        reevaluateScope()
    }

    /// Arms the live Spring Break destination fences.
    ///
    /// Only destinations whose server-dated window is currently live are armed.
    /// A destination out of window is not a place the app knows about.
    func configureSpringBreakDestinations(_ destinations: [SpringBreakDestination]) {
        springBreakDestinations = destinations.filter { $0.isLive() }

        // A destination that has dropped out of its window while we held
        // presence at it is a window end, not a fence exit — and it gets
        // different copy, because there is nothing the user can do about it.
        if let held = confirmedDestination, !held.isLive() {
            Task { @MainActor in await pauseSpringBreak(.windowEnded) }
            return
        }

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
            if confirmedDestination != nil {
                Task { @MainActor in await pauseSpringBreak(.leftFence) }
                return
            }
            if confirmedVisitingCampus != nil {
                Task { @MainActor in await pauseVisitingCampus(.leftFence) }
                return
            }
            // Home campus is not a paused state — it is the normal one. Clearing
            // both statuses here stops a stale banner following the user back to
            // their own school.
            springBreakStatus = .inactive
            visitingCampusStatus = .inactive
            suppressDestinationClaims = false
            suppressCampusClaims = false
            setScope(.campus(schoolId: campus.schoolId))
            return
        }

        // Standing on someone else's campus. Checked before Spring Break because
        // a campus is a stronger, year-round signal than a dated window, and the
        // two are unlikely to overlap anyway.
        if let visiting = allCampuses.first(where: { school in
            school.id != campus?.schoolId
                && containsLocation(location,
                                    geohash: school.campus.centerGeohash,
                                    radius: school.campus.radiusMeters)
        }) {
            if suppressCampusClaims {
                setScope(.none)
                return
            }
            Task { @MainActor in await claimVisitingCampus(visiting) }
            return
        }

        if confirmedVisitingCampus != nil {
            Task { @MainActor in await pauseVisitingCampus(.leftFence) }
            return
        }

        if let destination = springBreakDestinations.first(where: {
            $0.isLive() && containsLocation(location,
                                            geohash: $0.centerGeohash,
                                            radius: $0.radiusMeters)
        }) {
            // A pause suppresses re-claiming until the user actually leaves the
            // region or restarts Quest Mode; otherwise every location update
            // would retry against a backend that just said no.
            if suppressDestinationClaims {
                setScope(.none)
                return
            }
            Task { @MainActor in await claimDestination(destination) }
            return
        }

        if confirmedDestination != nil {
            Task { @MainActor in await pauseSpringBreak(.leftFence) }
            return
        }
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
            // Server said no. Pause explicitly rather than dropping to .none in
            // silence — the user is standing at the destination and would
            // otherwise have no way to tell the pool had closed.
            confirmedDestination = destination
            await pauseSpringBreak(.refreshFailed)
            return
        }

        confirmedDestination = destination
        springBreakStatus = .active(destinationId: id, displayLabel: label)
        setScope(.springBreak(destinationId: id, displayLabel: label))
        startDestinationRefresh()
    }

    /// Drops destination presence on the server and locally.
    @MainActor
    private func releaseDestination() async {
        confirmedDestination = nil
        stopDestinationRefresh()
        await SchoolGateManager.shared.clearDestinationPresence()
    }

    // MARK: - Visiting Campus Presence

    /// Confirms presence on another school's campus and opens its pool.
    ///
    /// Being inside the fence is necessary but not sufficient: the pool opens on
    /// a claim only `confirmCampusPresence` can issue, after it re-checks the
    /// school document's own centre and radius. A tampered client that skips this
    /// call holds a claimless token and reads nothing.
    @MainActor
    private func claimVisitingCampus(_ school: School) async {
        guard let schoolId = school.id else { return }
        guard confirmedVisitingCampus?.id != schoolId else { return }
        guard let geohash = currentGeohash else { return }

        guard let confirmation = await SchoolGateManager.shared
            .confirmCampusPresence(schoolId: schoolId, geohash: geohash) else {
            confirmedVisitingCampus = school
            await pauseVisitingCampus(.refreshFailed)
            return
        }

        confirmedVisitingCampus = school
        visitingCampusStatus = .active(schoolId: schoolId, displayName: confirmation.name)
        setScope(.campus(schoolId: schoolId))
        startCampusRefresh()
    }

    /// Re-confirms the visiting claim every 15 minutes, inside its 45-minute TTL.
    ///
    /// Identical cadence and reasoning to the destination refresh: an unrefreshed
    /// claim would expire silently and the pool would narrow with nothing on
    /// screen to explain it.
    private func startCampusRefresh() {
        stopCampusRefresh()
        campusRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.destinationRefreshSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.refreshVisitingCampus()
            }
        }
    }

    private func stopCampusRefresh() {
        campusRefreshTask?.cancel()
        campusRefreshTask = nil
    }

    @MainActor
    private func refreshVisitingCampus() async {
        guard let school = confirmedVisitingCampus, let schoolId = school.id else {
            stopCampusRefresh()
            return
        }

        guard isScanning else {
            await pauseVisitingCampus(.questModeOff)
            return
        }

        guard let location = currentLocation,
              containsLocation(location,
                               geohash: school.campus.centerGeohash,
                               radius: school.campus.radiusMeters) else {
            await pauseVisitingCampus(.leftFence)
            return
        }

        guard let geohash = currentGeohash,
              let confirmation = await SchoolGateManager.shared
                .confirmCampusPresence(schoolId: schoolId, geohash: geohash) else {
            await pauseVisitingCampus(.refreshFailed)
            return
        }

        visitingCampusStatus = .active(schoolId: schoolId, displayName: confirmation.name)
        setScope(.campus(schoolId: schoolId))
        Log.location.debug("Visiting campus presence refreshed")
    }

    /// Closes the visiting pool and says so.
    @MainActor
    private func pauseVisitingCampus(_ reason: VisitingCampusStatus.PauseReason) async {
        let name = confirmedVisitingCampus?.displayName
            ?? visitingCampusStatus.schoolDisplayName
            ?? "that campus"

        confirmedVisitingCampus = nil
        stopCampusRefresh()
        await SchoolGateManager.shared.clearCampusPresence()

        suppressCampusClaims = true
        visitingCampusStatus = .paused(displayName: name, reason: reason)

        // Back to the home campus if they are on it, otherwise paused. No
        // leftover cross-school radar either way.
        if let campus, let location = currentLocation,
           containsLocation(location,
                            geohash: campus.geofence.centerGeohash,
                            radius: campus.geofence.radiusMeters) {
            visitingCampusStatus = .inactive
            suppressCampusClaims = false
            setScope(.campus(schoolId: campus.schoolId))
        } else {
            setScope(.none)
        }

        Log.location.debug("Visiting campus presence paused")
    }

    // MARK: - Presence Refresh

    /// Re-confirms `sbDest` every 15 minutes while presence is held.
    ///
    /// The claim the backend issues is short-lived by design, so that a user who
    /// flies home cannot keep reading a cross-school pool. That makes an
    /// unrefreshed claim a silent expiry — the pool would simply stop returning
    /// other schools with nothing on screen to explain it. This loop is what
    /// turns that into either a live claim or a visible paused state.
    private func startDestinationRefresh() {
        stopDestinationRefresh()
        destinationRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.destinationRefreshSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.refreshDestinationPresence()
            }
        }
    }

    private func stopDestinationRefresh() {
        destinationRefreshTask?.cancel()
        destinationRefreshTask = nil
    }

    /// One refresh tick.
    ///
    /// Every precondition is re-checked locally before the round-trip, and then
    /// again by the backend, which re-decodes the geohash against the
    /// destination's own centre, radius and dated window. A refresh cannot
    /// extend presence the user no longer has.
    @MainActor
    private func refreshDestinationPresence() async {
        guard let destination = confirmedDestination else {
            stopDestinationRefresh()
            return
        }

        guard isScanning else {
            await pauseSpringBreak(.questModeOff)
            return
        }

        guard destination.isLive() else {
            await pauseSpringBreak(.windowEnded)
            return
        }

        guard let location = currentLocation,
              containsLocation(location,
                               geohash: destination.centerGeohash,
                               radius: destination.radiusMeters) else {
            await pauseSpringBreak(.leftFence)
            return
        }

        guard let id = destination.id, let geohash = currentGeohash else {
            await pauseSpringBreak(.refreshFailed)
            return
        }

        guard let label = await SchoolGateManager.shared
            .confirmDestinationPresence(destinationId: id, geohash: geohash) else {
            await pauseSpringBreak(.refreshFailed)
            return
        }

        springBreakStatus = .active(destinationId: id, displayLabel: label)
        setScope(.springBreak(destinationId: id, displayLabel: label))
        Log.location.debug("Destination presence refreshed")
    }

    /// Closes the cross-school pool and says so.
    ///
    /// Order matters: presence is released on the server first, so the claim and
    /// the profile flag are gone before the scope narrows. Otherwise a crash in
    /// between would leave a live claim with no local record of it.
    @MainActor
    private func pauseSpringBreak(_ reason: SpringBreakStatus.PauseReason) async {
        let label = confirmedDestination.map(\.displayLabel)
            ?? springBreakStatus.displayLabel
            ?? "Spring Break"

        await releaseDestination()

        // Stops reevaluateScope re-claiming the same fence on the next location
        // update, which would loop against a backend that just declined.
        suppressDestinationClaims = true
        springBreakStatus = .paused(displayLabel: label, reason: reason)

        // Back to same-school: campus if they are on it, otherwise paused.
        // No leftover cross-school radar either way.
        if let campus, let location = currentLocation,
           containsLocation(location,
                            geohash: campus.geofence.centerGeohash,
                            radius: campus.geofence.radiusMeters) {
            setScope(.campus(schoolId: campus.schoolId))
        } else {
            setScope(.none)
        }

        Log.location.debug("Spring Break presence paused")
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

        // Actually leaving a destination is a real signal, so a later re-entry
        // should get a fresh attempt rather than inheriting an old pause.
        if region.identifier.hasPrefix(Self.destinationRegionPrefix) {
            suppressDestinationClaims = false
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
