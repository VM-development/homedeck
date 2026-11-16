import CoreBluetooth
import HubCore
import MiScaleKit
import SwiftUI

/// One weigh-in, assembled from the frames that share the scale's timestamp.
struct WeighIn: Codable, Identifiable, Equatable {
    let scaleTime: UInt32
    let date: Date
    var profileID: Int
    var weight: Double
    var heartRate: Int?
    var impedance50: Double?
    var impedance250: Double?

    var id: UInt32 { scaleTime }
}

/// The S400 never connects: it broadcasts each weigh-in in encrypted advertisements, which HomeDeck decrypts
/// with the bind key and MAC from the owner's Xiaomi account.
@MainActor
@Observable
final class MiScaleDevice: NSObject, HomeDevice {
    static let id = "mi-scale-s400"
    private static let keyAccount = "mi-scale-s400.bindkey"
    private static let macAccount = "mi-scale-s400.mac"
    private static let weighInsKey = "mi-scale-s400.weighins"
    private static let service = CBUUID(string: MiBeacon.serviceUUID)

    private(set) var status: DeviceStatus = .notSetUp
    private(set) var weighIns: [WeighIn] = []
    /// When any S400 frame was last heard, set up or not: shows the owner that listening works.
    private(set) var lastHeard: Date?
    private(set) var decryptFailed = false

    @ObservationIgnored private var key: [UInt8]?
    @ObservationIgnored private var mac: [UInt8]?
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var lastCounter: [UUID: UInt8] = [:]
    /// Encrypted frames heard before the key was entered, decrypted as soon as it is.
    @ObservationIgnored private var unread: [MiBeacon] = []
    @ObservationIgnored private let log = ConnectionLog.shared.tagged(MiScaleDevice.id)
    @ObservationIgnored private let defaults = UserDefaults.standard

    override init() {
        super.init()
        weighIns = defaults.data(forKey: Self.weighInsKey).flatMap { try? JSONDecoder().decode([WeighIn].self, from: $0) } ?? []
        key = Keychain.get(Self.keyAccount).flatMap { MiBeacon.hexBytes($0, count: 16) }
        mac = Keychain.get(Self.macAccount).flatMap { MiBeacon.hexBytes($0, count: 6) }
        // Only a scale set up before listens from launch: no permission prompt, and background capture keeps working.
        if key != nil, mac != nil {
            updateStatus()
            startCentral()
        }
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scan() }
            }
        }
    }

    var isSetUp: Bool { key != nil && mac != nil }
    /// True once the scale's own broadcast told us its MAC.
    var knowsMAC: Bool { mac != nil }

    // MARK: HomeDevice

    func connect() async {}
    func disconnect() async {}
    func makeScreen() -> AnyView { AnyView(MiScaleScreen(scale: self)) }

    // MARK: Setup

    /// Starts listening while the setup screen is open, so the owner sees the scale is heard before entering keys.
    func listen() {
        if central == nil { startCentral() }
    }

    /// Returns an error message, or nil when saved.
    /// An empty MAC keeps the one the scale broadcast.
    func setUp(key keyText: String, mac macText: String) -> String? {
        guard let key = MiBeacon.hexBytes(keyText, count: 16) else { return "The bind key is 32 hex characters." }
        if !macText.isEmpty || mac == nil {
            guard let typed = MiBeacon.hexBytes(macText, count: 6) else {
                return "The MAC address is 12 hex characters, like AA:BB:CC:DD:EE:FF."
            }
            saveMAC(typed)
        }
        Keychain.set(keyText.filter(\.isHexDigit), for: Self.keyAccount)
        self.key = key
        decryptFailed = false
        updateStatus()
        log.add("bind key saved")
        let waiting = unread
        unread = []
        waiting.forEach(decrypt)
        listen()
        return nil
    }

    private func saveMAC(_ mac: [UInt8]) {
        self.mac = mac
        Keychain.set(mac.map { String(format: "%02X", $0) }.joined(), for: Self.macAccount)
    }

    func forget() {
        Keychain.set(nil, for: Self.keyAccount)
        Keychain.set(nil, for: Self.macAccount)
        key = nil
        mac = nil
        status = .notSetUp
        log.add("bind key and MAC removed")
    }

    // MARK: Bluetooth

    private func startCentral() {
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "homedeck.\(Self.id)"])
    }

    /// Foreground: every advertisement, since whether iOS matches an FE95 filter to service data is unknown.
    /// Background: iOS requires a service filter.
    private func scan() {
        guard let central, central.state == .poweredOn else { return }
        let foreground = UIApplication.shared.applicationState != .background
        central.stopScan()
        central.scanForPeripherals(withServices: foreground ? nil : [Self.service],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        log.add("listening (\(foreground ? "all advertisements" : "FE95 only, background"))")
    }

    private func bluetoothChanged(_ state: CBManagerState) {
        log.add("bluetooth state \(state.rawValue)")
        switch state {
        case .poweredOn: scan()
        case .unauthorized: status = .offline(reason: "Bluetooth access for HomeDeck is off in Settings.")
        case .poweredOff: status = .offline(reason: "Bluetooth is off.")
        default: break
        }
    }

    private func heard(_ peripheral: CBPeripheral, advertisement: [String: Any], rssi: NSNumber) {
        guard let data = (advertisement[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data])?[Self.service],
              let beacon = MiBeacon(data), MiBeacon.s400ProductIDs.contains(beacon.productID),
              lastCounter[peripheral.identifier] != beacon.counter else { return }
        lastCounter[peripheral.identifier] = beacon.counter
        lastHeard = Date()
        log.add("<- \(beacon.redactedHex) (product \(String(format: "%04X", beacon.productID)), RSSI \(rssi))")
        if mac == nil, let heardMAC = beacon.mac {
            saveMAC(heardMAC)
            log.add("learned the MAC from the scale's idle frame")
        }
        guard beacon.isEncrypted, beacon.hasObjects else { return }
        guard key != nil, mac != nil else {
            unread = Array((unread + [beacon]).suffix(10))
            return
        }
        decrypt(beacon)
    }

    private func decrypt(_ beacon: MiBeacon) {
        guard let key, let mac else { return }
        guard let objects = beacon.objects(key: key, mac: mac) else {
            decryptFailed = true
            log.add("can't decrypt: wrong bind key or MAC, or another person's scale")
            return
        }
        decryptFailed = false
        for reading in S400Reading.readings(in: objects) { apply(reading) }
    }

    private func apply(_ reading: S400Reading) {
        log.add("reading: profile \(reading.profileID), \(reading.weight.map { "\($0) kg" } ?? "no weight"), "
                + "HR \(reading.heartRate.map(String.init) ?? "-"), \(reading.impedance.map { "\($0) ohm" } ?? "no impedance"), "
                + "time \(reading.timestamp)")
        guard !reading.isReset else { return }
        if let index = weighIns.firstIndex(where: { $0.scaleTime == reading.timestamp }) {
            if let weight = reading.weight {
                weighIns[index].weight = weight
                weighIns[index].profileID = reading.profileID
                weighIns[index].impedance50 = reading.impedance ?? weighIns[index].impedance50
                weighIns[index].heartRate = reading.heartRate ?? weighIns[index].heartRate
            } else {
                weighIns[index].impedance250 = reading.impedance
            }
        } else if let weight = reading.weight {
            weighIns.append(WeighIn(scaleTime: reading.timestamp, date: Self.date(reading.timestamp),
                                    profileID: reading.profileID, weight: weight, heartRate: reading.heartRate,
                                    impedance50: reading.impedance))
        } else {
            return  // second impedance without its weight frame
        }
        defaults.set(try? JSONEncoder().encode(weighIns), forKey: Self.weighInsKey)
        updateStatus()
    }

    /// The scale's clock is set by Xiaomi Home; trust it only when it's close to the phone's.
    private static func date(_ scaleTime: UInt32) -> Date {
        let date = Date(timeIntervalSince1970: TimeInterval(scaleTime))
        return abs(date.timeIntervalSinceNow) < 2 * 86_400 ? date : Date()
    }

    private func updateStatus() {
        guard isSetUp else { return }
        status = .online(summary: weighIns.last.map {
            "\($0.weight.formatted(.number.precision(.fractionLength(1)))) kg · \($0.date.formatted(.relative(presentation: .named)))"
        } ?? "Waiting for a weigh-in")
    }
}

extension MiScaleDevice: CBCentralManagerDelegate {
    // The central runs on the main queue (queue: nil), so every callback is already on the main actor.

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { bluetoothChanged(central.state) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated { log.add("restored by iOS") }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated { heard(peripheral, advertisement: advertisementData, rssi: RSSI) }
    }
}
