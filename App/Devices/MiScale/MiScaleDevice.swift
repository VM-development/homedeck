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
    /// Optional so weigh-ins saved before this field still decode.
    var savedToHealth: Bool?

    var id: UInt32 { scaleTime }
}

/// The person behind one of the scale's user slots. Kept only on this iPhone.
struct Person: Codable, Equatable, Identifiable {
    /// The scale's profile slot (1, 2, …).
    let id: Int
    var name = ""
    var heightCM: Double?
    var birthYear: Int?
    var male = true
    var savesToHealth = false

    var title: String { name.isEmpty ? "Person \(id)" : name }
    var age: Int? { birthYear.map { Calendar.current.component(.year, from: Date()) - $0 } }
    var details: String? {
        guard let heightCM, let age else { return nil }
        return "\(Int(heightCM)) cm · \(age) · \(male ? "male" : "female")"
    }
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
    private static let peopleKey = "mi-scale-s400.people"
    private static let service = CBUUID(string: MiBeacon.serviceUUID)

    private(set) var status: DeviceStatus = .notSetUp
    private(set) var weighIns: [WeighIn] = []
    private(set) var people: [Person] = []
    /// When any S400 frame was last heard, set up or not: shows the owner that listening works.
    private(set) var lastHeard: Date?
    private(set) var decryptFailed = false

    private var key: [UInt8]?
    private var mac: [UInt8]?
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var lastCounter: [UUID: UInt8] = [:]
    /// Encrypted frames heard before the key was entered, decrypted as soon as it is.
    @ObservationIgnored private var unread: [MiBeacon] = []
    @ObservationIgnored private var healthSave: Task<Void, Never>?
    @ObservationIgnored private let log = ConnectionLog.shared.tagged(MiScaleDevice.id)
    @ObservationIgnored private let defaults = UserDefaults.standard

    override init() {
        super.init()
        weighIns = defaults.data(forKey: Self.weighInsKey).flatMap { try? JSONDecoder().decode([WeighIn].self, from: $0) } ?? []
        people = defaults.data(forKey: Self.peopleKey).flatMap { try? JSONDecoder().decode([Person].self, from: $0) } ?? []
        key = Keychain.get(Self.keyAccount).flatMap { MiBeacon.hexBytes($0, count: 16) }
        mac = Keychain.get(Self.macAccount).flatMap { MiBeacon.hexBytes($0, count: 6) }
        // Only a scale set up before listens from launch: no permission prompt, and background capture keeps working.
        if key != nil, mac != nil {
            updateStatus()
            startCentral()
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

    /// iOS matches the FE95 filter against the scale's service data (seen on device), and the background needs a filter.
    private func scan() {
        guard let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [Self.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        log.add("listening for FE95")
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
        saveWeighIns()
        updateStatus()
        // A weigh-in arrives in two or three frames; save it to Health once they've stopped coming.
        healthSave?.cancel()
        healthSave = Task {
            try? await Task.sleep(for: .seconds(20))
            if !Task.isCancelled { await saveToHealth(reading.timestamp) }
        }
    }

    private func saveWeighIns() {
        defaults.set(try? JSONEncoder().encode(weighIns), forKey: Self.weighInsKey)
    }

    // MARK: People and Health

    /// Every profile slot seen on the scale or edited, guests (slot 0) excluded.
    var profileIDs: [Int] {
        Set(weighIns.map(\.profileID) + people.map(\.id)).filter { $0 != 0 }.sorted()
    }

    func person(_ id: Int) -> Person { people.first { $0.id == id } ?? Person(id: id) }

    func composition(for weighIn: WeighIn) -> BodyComposition? {
        let p = person(weighIn.profileID)
        guard weighIn.profileID != 0, let height = p.heightCM, let age = p.age else { return nil }
        return BodyComposition(weight: weighIn.weight, impedance: weighIn.impedance50, heightCM: height, age: age, male: p.male)
    }

    func save(_ person: Person) async {
        var person = person
        if person.savesToHealth, !(await HealthSaver.requestAccess()) {
            person.savesToHealth = false
            log.add("Apple Health access not granted")
        }
        // Apple Health belongs to this iPhone's owner: only one person saves to it.
        if person.savesToHealth { for i in people.indices { people[i].savesToHealth = false } }
        people.removeAll { $0.id == person.id }
        people.append(person)
        people.sort { $0.id < $1.id }
        savePeople()
    }

    /// The id for a person added in HomeDeck. ponytail: ids double as the scale's numbers, so a person added
    /// second gets the scale's person 2; matching by weight would decouple them if the scale's numbers don't fit.
    var nextPersonID: Int { (profileIDs.max() ?? 0) + 1 }

    /// Their weigh-ins move to Guest, from where they can be moved back.
    func remove(_ id: Int) {
        people.removeAll { $0.id == id }
        savePeople()
        for i in weighIns.indices where weighIns[i].profileID == id { weighIns[i].profileID = 0 }
        saveWeighIns()
        log.add("removed profile \(id)")
    }

    /// The scale can pick the wrong person, or nobody (Guest): the owner moves the weigh-in by hand.
    /// ponytail: a weigh-in already in Apple Health stays there; delete it in Health if it was someone else's.
    func move(_ weighIn: WeighIn, to id: Int) {
        guard let index = weighIns.firstIndex(where: { $0.scaleTime == weighIn.scaleTime }) else { return }
        weighIns[index].profileID = id
        saveWeighIns()
        log.add("weigh-in moved to profile \(id)")
        Task { await saveToHealth(weighIn.scaleTime) }
    }

    private func savePeople() {
        defaults.set(try? JSONEncoder().encode(people), forKey: Self.peopleKey)
    }

    private func saveToHealth(_ scaleTime: UInt32) async {
        guard let index = weighIns.firstIndex(where: { $0.scaleTime == scaleTime }), weighIns[index].savedToHealth != true,
              person(weighIns[index].profileID).savesToHealth else { return }
        let weighIn = weighIns[index]
        do {
            try await HealthSaver.save(weighIn, composition: composition(for: weighIn))
            weighIns[index].savedToHealth = true
            saveWeighIns()
            log.add("saved the weigh-in to Apple Health")
        } catch {
            log.add("Apple Health save failed: \(error.localizedDescription)")
        }
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
