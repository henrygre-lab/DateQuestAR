// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] No raw coordinates transmitted — BLE service UUID is app-scoped, not location-bearing
// [x] accountStatus checked before any proximity alert — waitlisted users get nothing
// [x] Intent/vibe pre-filter applied before alerts fire — reduces unwanted contact
// [x] Squad radar mode defaults when socialContextPreference == true or density is high
// [x] No PII in BLE advertisements — only app service UUID and generic local name
// [x] Per-user profile data never transmitted over BLE — only matched via Firestore UID
// [x] No mutable public user state — profile passed explicitly to all filtering methods
// [x] Same-school gate before any proximity alert — shouldFireProximityAlert runs
//     CommunityGate.canShare against the current CommunityScope, so a BLE or UWB
//     advertisement from another campus is discarded rather than matched
// [x] Off campus (scope .none) no proximity alert can fire at all
// [x] Gender-balance throttling applies only to Dating-gated pairs
// [x] Squad Radar is the default after dusk inside a Spring Break destination
// [x] NearbyInteraction discovery tokens are per-session and never persisted
// [x] Analytics events contain no raw UIDs or PII

import Foundation
import CoreBluetooth
import NearbyInteraction
import Combine

// MARK: - ProximityService (UWB + Bluetooth)

final class ProximityService: NSObject, ObservableObject {
    static let shared = ProximityService()

    @Published var nearbyDevices: [NearbyDevice] = []
    @Published var isSquadRadarMode: Bool = false

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private var niSession: NISession?           // UWB via NearbyInteraction
    private let serviceUUID = CBUUID(string: "DQ-AR-0001-0000-0000-000000000001")

    /// Density threshold: when this many users share the same geohash prefix, switch to squad radar.
    private let highDensityThreshold: Int = 10

    private let analytics = AnalyticsService.shared

    /// Account status of the active user, set via configureForUser().
    /// Used by BLE delegate callbacks that cannot accept parameters.
    private var activeUserAccountStatus: AccountStatus = .active

    struct NearbyDevice: Identifiable {
        var id: String                          // Mapped to Firebase UID via token exchange
        var distance: Float?                    // UWB distance in meters
        var rssi: Int                           // Bluetooth RSSI fallback
    }

    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .global(qos: .background),
                                          options: [CBCentralManagerOptionShowPowerAlertKey: true])
        peripheralManager = CBPeripheralManager(delegate: self, queue: .global(qos: .background))
    }

    // MARK: - Configuration

    /// Called by the view layer to set the active user's account status.
    /// Only stores the minimal field needed for BLE delegate gating.
    func configureForUser(accountStatus: AccountStatus) {
        activeUserAccountStatus = accountStatus
    }

    // MARK: - Squad Radar Mode

    /// Evaluates whether squad radar mode should be active.
    ///
    /// `forceSquadRadar` is set after dusk inside a Spring Break destination,
    /// where people arrive in groups and should stay in them. It overrides the
    /// user preference in the permissive direction only — it can switch squad
    /// mode on, never off.
    @MainActor
    func evaluateSquadRadarMode(prefersSocialContext: Bool,
                                nearbyCount: Int,
                                forceSquadRadar: Bool = false) {
        let wasEnabled = isSquadRadarMode
        if forceSquadRadar || prefersSocialContext || nearbyCount >= highDensityThreshold {
            isSquadRadarMode = true
        } else {
            isSquadRadarMode = false
        }

        // Log when squad radar mode changes
        if isSquadRadarMode != wasEnabled {
            analytics.logSquadRadarToggled(enabled: isSquadRadarMode, nearbyCount: nearbyCount)
        }
    }

    // MARK: - Pre-Alert Filters

    /// Checks all pre-conditions before a proximity alert should fire.
    /// Returns true only if the alert should proceed.
    ///
    /// Radio proximity is not membership. Anyone standing within BLE range can
    /// advertise — another campus's student, a local, a passer-by — so the
    /// community gate runs first and cheapest, before any scoring work.
    @MainActor
    func shouldFireProximityAlert(
        currentUser: UserProfile,
        candidate: UserProfile
    ) -> Bool {
        // 1. Account status gate — waitlisted/suspended/banned get no alerts
        guard currentUser.accountStatus == .active else { return false }
        guard candidate.accountStatus == .active else { return false }

        // 2. Same school, or the same live Spring Break destination. Off campus
        //    the scope is .none and this fails for everyone.
        guard CommunityGate.canShare(viewer: currentUser,
                                     candidate: candidate,
                                     in: LocationService.shared.communityScope) else {
            return false
        }

        // 3. Some shared reason to meet.
        let locked = EncounterSession.lockIntents(currentUser, candidate)
        guard !locked.isEmpty else { return false }

        // 4. Intent/vibe pre-filter via MatchManager's scoring
        let vibeScore = MatchManager.shared.scoreVibeCompatibility(
            currentUser.intentVibes, candidate.intentVibes
        )
        guard vibeScore >= 0.6 else {
            analytics.logVibeFilterRejected(vibeScore: vibeScore)
            return false
        }

        // 5. BalanceEnforcer visibility gate — Dating overlaps only.
        if Intent.engagesGenderBalance(locked) {
            guard BalanceEnforcer.shared.shouldShowMatch(to: currentUser) else { return false }
        }

        return true
    }

    // MARK: - UWB Session

    func startUWBSession(with token: NIDiscoveryToken) {
        // Check if device supports UWB using the modern API
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            Log.proximity.debug("UWB not supported on this device. Falling back to BLE RSSI.")
            return
        }
        niSession = NISession()
        niSession?.delegate = self
        let config = NINearbyPeerConfiguration(peerToken: token)
        niSession?.run(config)
    }

    func stopUWBSession() {
        niSession?.invalidate()
        niSession = nil
    }

    // MARK: - BLE Advertising (Discovery beacon)

    func startAdvertising() {
        guard activeUserAccountStatus == .active else { return }
        guard peripheralManager.state == .poweredOn else { return }
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "Serendipity"
        ])
    }

    func stopAdvertising() {
        peripheralManager.stopAdvertising()
    }

    // MARK: - BLE Scanning

    func startScanning() {
        guard activeUserAccountStatus == .active else { return }
        guard centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(withServices: [serviceUUID],
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScanning() {
        centralManager.stopScan()
    }

    // MARK: - RSSI to Distance

    private func estimateDistance(rssi: Int, txPower: Int = -59) -> Double {
        guard rssi != 0 else { return -1 }
        let ratio = Double(rssi) / Double(txPower)
        if ratio < 1.0 { return pow(ratio, 10) }
        return 0.89976 * pow(ratio, 7.7095) + 0.111
    }
}

// MARK: - CBCentralManagerDelegate

extension ProximityService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { startScanning() }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let dist = estimateDistance(rssi: RSSI.intValue)
        let device = NearbyDevice(id: peripheral.identifier.uuidString,
                                  distance: Float(dist),
                                  rssi: RSSI.intValue)
        DispatchQueue.main.async {
            if let idx = self.nearbyDevices.firstIndex(where: { $0.id == device.id }) {
                self.nearbyDevices[idx] = device
            } else {
                self.nearbyDevices.append(device)
            }
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension ProximityService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn { startAdvertising() }
    }
}

// MARK: - NISessionDelegate (UWB)

extension ProximityService: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        for obj in nearbyObjects {
            guard let dist = obj.distance else { continue }
            Log.proximity.debug("Peer distance: \(dist)m")
            // TODO: Map token to UID and update activeMatches in MatchManager
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        Log.proximity.error("Session invalidated: \(error)")
    }
}
