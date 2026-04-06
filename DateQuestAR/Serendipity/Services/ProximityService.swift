import Foundation
import CoreBluetooth
import NearbyInteraction
import Combine

// MARK: - ProximityService (UWB + Bluetooth)

final class ProximityService: NSObject, ObservableObject {
    static let shared = ProximityService()

    @Published var nearbyDevices: [NearbyDevice] = []

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private var niSession: NISession?           // UWB via NearbyInteraction
    private let serviceUUID = CBUUID(string: "DQ-AR-0001-0000-0000-000000000001")

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

    // MARK: - UWB Session

    func startUWBSession(with token: NIDiscoveryToken) {
        // Check if device supports UWB using the modern API
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            print("[Proximity] UWB not supported on this device. Falling back to BLE RSSI.")
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
            print("[UWB] Peer distance: \(dist)m")
            // TODO: Map token to UID and update activeMatches in MatchManager
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        print("[UWB] Session invalidated: \(error)")
    }
}
