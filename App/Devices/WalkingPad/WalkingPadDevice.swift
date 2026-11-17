import CoreBluetooth
import HubCore
import SwiftUI
import WalkingPadKit

/// A walk HomeDeck saw end. The C2 answers the stored-walk request with an empty record, so HomeDeck keeps its own.
struct Walk: Codable, Identifiable, Equatable {
    /// When the belt stopped.
    let date: Date
    let seconds: Int
    let meters: Int
    let steps: Int

    var id: Date { date }
}

/// The WalkingPad C2 over Bluetooth. Polls status every 0.75 s while connected; commands take the next poll slot,
/// so writes stay at least 0.75 s apart, as the pad needs.
@MainActor
@Observable
final class WalkingPadDevice: NSObject, HomeDevice {
    static let id = "walkingpad-c2"
    private static let peripheralKey = "walkingpad-c2.peripheral"
    private static let walksKey = "walkingpad-c2.walks"

    private(set) var status: DeviceStatus = .notSetUp
    private(set) var live: WalkingPad.Status?
    private(set) var walks: [Walk] = []
    private(set) var isSearching = false
    /// Shown until the pad's status confirms them.
    private(set) var pendingMode: WalkingPad.Mode?
    private(set) var targetSpeed: Double?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var pad: CBPeripheral?
    @ObservationIgnored private var writer: CBCharacteristic?
    @ObservationIgnored private var session: Task<Void, Never>?
    @ObservationIgnored private var queue: [Data] = []
    /// The pad's counters when the belt started; they don't reset between walks until standby.
    @ObservationIgnored private var walkStart: WalkingPad.Status?
    @ObservationIgnored private var pendingSince = Date.distantPast
    @ObservationIgnored private let log = ConnectionLog.shared.tagged(WalkingPadDevice.id)
    @ObservationIgnored private let defaults = UserDefaults.standard

    override init() {
        super.init()
        walks = defaults.data(forKey: Self.walksKey).flatMap { try? JSONDecoder().decode([Walk].self, from: $0) } ?? []
        // Only a pad set up before starts Bluetooth at launch: no permission prompt, and iOS can restore it in the background.
        if savedID != nil {
            status = .offline(reason: nil)
            startCentral()
        }
    }

    private var savedID: UUID? { defaults.string(forKey: Self.peripheralKey).flatMap(UUID.init) }

    // MARK: HomeDevice

    func makeScreen() -> AnyView { AnyView(WalkingPadScreen(pad: self)) }

    // MARK: Setup

    func search() {
        isSearching = true
        status = .connecting
        if let central { if central.state == .poweredOn { scan() } } else { startCentral() }
    }

    func forget() {
        session?.cancel()
        if let pad { central?.cancelPeripheralConnection(pad) }
        pad = nil
        writer = nil
        live = nil
        defaults.removeObject(forKey: Self.peripheralKey)
        status = .notSetUp
        log.add("forgot the pad")
    }

    // MARK: Controls

    func start() {
        // A pad in standby ignores start; switch to manual first, one poll slot apart.
        if live?.mode == WalkingPad.Mode.standby.rawValue {
            enqueue(WalkingPad.setMode(.manual))
            enqueue(WalkingPad.askStatus)
        }
        enqueue(WalkingPad.start)
    }

    func stop() {
        targetSpeed = nil
        enqueue(WalkingPad.stop)
    }

    func setSpeed(_ kmh: Double) {
        targetSpeed = min(max(kmh, WalkingPad.speedRange.lowerBound), WalkingPad.speedRange.upperBound)
        pendingSince = Date()
        enqueue(WalkingPad.setSpeed(kmh))
    }

    func setMode(_ mode: WalkingPad.Mode) {
        pendingMode = mode
        pendingSince = Date()
        enqueue(WalkingPad.setMode(mode))
    }

    /// A newer command of the same kind replaces a queued one (speed taps, stop after speed: both are "A2 01").
    private func enqueue(_ frame: Data) {
        queue.removeAll { $0.prefix(3) == frame.prefix(3) }
        queue.append(frame)
    }

    // MARK: Bluetooth

    private func startCentral() {
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "homedeck.\(Self.id)"])
    }

    private func scan() {
        log.add("searching for service \(WalkingPad.service)")
        central?.scanForPeripherals(withServices: [CBUUID(string: WalkingPad.service)])
        Task {
            try? await Task.sleep(for: .seconds(20))
            guard isSearching else { return }
            central?.stopScan()
            isSearching = false
            status = savedID == nil ? .notSetUp : .offline(reason: nil)
            log.add("no pad found in 20 s")
        }
    }

    private func bluetoothChanged(_ state: CBManagerState) {
        log.add("bluetooth state \(state.rawValue)")
        switch state {
        case .poweredOn:
            if isSearching { scan() } else { reconnect() }
        case .unauthorized:
            isSearching = false
            status = .offline(reason: "Bluetooth access for HomeDeck is off in Settings.")
        case .poweredOff:
            isSearching = false
            status = .offline(reason: "Bluetooth is off.")
        default:
            break
        }
    }

    /// A pending connect never times out: iOS connects as soon as the pad is on and in range.
    private func reconnect() {
        guard let central, let id = savedID else { return }
        if pad == nil { pad = central.retrievePeripherals(withIdentifiers: [id]).first }
        guard let pad else { return }
        pad.delegate = self
        if pad.state == .connected { pad.discoverServices(nil) } else { central.connect(pad) }
    }

    private func found(_ peripheral: CBPeripheral, rssi: NSNumber) {
        guard isSearching else { return }
        central?.stopScan()
        isSearching = false
        log.add("found \(peripheral.name ?? "unnamed"), RSSI \(rssi)")
        defaults.set(peripheral.identifier.uuidString, forKey: Self.peripheralKey)
        pad = peripheral
        peripheral.delegate = self
        central?.connect(peripheral)
    }

    private func connected(_ peripheral: CBPeripheral) {
        log.add("connected")
        status = .connecting
        peripheral.discoverServices(nil)  // all of them: the log answers whether the C2 has more than FE00
    }

    private func disconnected(_ error: Error?) {
        session?.cancel()
        writer = nil
        live = nil
        pendingMode = nil
        targetSpeed = nil
        log.add("disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")")
        guard savedID != nil else { return }
        status = .offline(reason: error?.localizedDescription)
        reconnect()
    }

    private func discoveredServices(_ peripheral: CBPeripheral) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    private func discoveredCharacteristics(_ service: CBService, _ peripheral: CBPeripheral) {
        let chars = (service.characteristics ?? []).map { "\($0.uuid) \(Self.describe($0.properties))" }
        log.add("service \(service.uuid): \(chars.joined(separator: "; "))")
        guard service.uuid == CBUUID(string: WalkingPad.service) else { return }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == CBUUID(string: WalkingPad.writeCharacteristic) { writer = characteristic }
            if characteristic.uuid == CBUUID(string: WalkingPad.notifyCharacteristic) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    private func notifying(_ characteristic: CBCharacteristic, _ error: Error?) {
        guard characteristic.uuid == CBUUID(string: WalkingPad.notifyCharacteristic) else { return }
        if let error { log.add("subscribe failed: \(error.localizedDescription)") }
        guard characteristic.isNotifying else { return }
        log.add("subscribed to \(WalkingPad.notifyCharacteristic)")
        startSession()
    }

    private func startSession() {
        session?.cancel()
        queue = []
        // ponytail: no handshake; the C2 answers the first poll (other KingSmith pads may need profile + beep first).
        session = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                send(queue.isEmpty ? WalkingPad.askStatus : queue.removeFirst())
                try? await Task.sleep(for: .milliseconds(750))
            }
        }
    }

    private func send(_ frame: Data) {
        guard let pad, let writer else { return }
        pad.writeValue(frame, for: writer, type: .withoutResponse)
        if frame != WalkingPad.askStatus { log.add("-> \(frame.hex)") }
    }

    private func received(_ data: Data) {
        switch WalkingPad.decode(data) {
        case .status(let new):
            settlePending(new)
            let online = DeviceStatus.online(summary: Self.summary(new))
            if status != online { status = online }
            guard new != live else { return }  // the same status every 0.75 s: don't redraw or log it
            log.add("<- \(data.hex)")
            if new.isRunning && live?.isRunning != true { walkStart = live ?? new }
            if !new.isRunning, live?.isRunning == true, let start = walkStart {
                save(Walk(date: Date(), seconds: max(0, new.seconds - start.seconds),
                          meters: max(0, new.meters - start.meters), steps: max(0, new.steps - start.steps)))
                walkStart = nil
            }
            live = new
        case .other:
            log.add("<- \(data.hex)")
        case nil:
            log.add("<- \(data.hex) (not a frame we know)")
        }
    }

    private func settlePending(_ new: WalkingPad.Status) {
        let expired = Date().timeIntervalSince(pendingSince) > 5
        if let mode = pendingMode, new.mode == mode.rawValue || expired { pendingMode = nil }
        if let speed = targetSpeed, abs(new.speed - speed) < 0.05 || !new.isRunning || expired { targetSpeed = nil }
    }

    private func save(_ walk: Walk) {
        guard walk.seconds > 0 else { return }
        walks.append(walk)
        log.add("saved a walk: \(walk.seconds) s, \(walk.meters) m, \(walk.steps) steps")
        defaults.set(try? JSONEncoder().encode(walks), forKey: Self.walksKey)
    }

    private static func summary(_ s: WalkingPad.Status) -> String {
        if s.isRunning { return "Walking · \(s.speed.formatted(.number.precision(.fractionLength(1)))) km/h" }
        if s.isCountingDown { return "Starting…" }
        if s.mode == WalkingPad.Mode.standby.rawValue { return "Standby" }
        return "Connected · stopped"
    }

    private static func describe(_ p: CBCharacteristicProperties) -> String {
        [(CBCharacteristicProperties.read, "read"), (.write, "write"), (.writeWithoutResponse, "writeNoResponse"),
         (.notify, "notify"), (.indicate, "indicate")].filter { p.contains($0.0) }.map(\.1).joined(separator: ",")
    }
}

extension WalkingPadDevice: CBCentralManagerDelegate, CBPeripheralDelegate {
    // The central runs on the main queue (queue: nil), so every callback is already on the main actor.

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { bluetoothChanged(central.state) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated {
            pad = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first
            pad?.delegate = self
            log.add("restored by iOS")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated { found(peripheral, rssi: RSSI) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { connected(peripheral) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { disconnected(error) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated { disconnected(error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated { discoveredServices(peripheral) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated { discoveredCharacteristics(service, peripheral) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated { notifying(characteristic, error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard let data = characteristic.value else { return }
        MainActor.assumeIsolated { received(data) }
    }
}
