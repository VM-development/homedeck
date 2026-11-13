import AVFoundation
import CoreBluetooth
import Rex5Kit

/// Bluetooth LE control link to the Rex5. Finds the earbuds, sends GAIA packets and routes what comes back.
/// Connects only while the earbuds' audio is up: an LE link made first stops the audio link from
/// coming back (connection log, 2026-11-11), so there is no standing reconnect.
@MainActor
final class EarbudLink: NSObject {
    enum State: Equatable {
        case bluetoothOff(String)
        case waitingForAudio
        case searching
        case notFound
        case connecting
        case ready
        case paused
    }

    enum LinkError: LocalizedError {
        case notReady
        case timeout(UInt16)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .notReady: return "The earbuds are not connected."
            case .timeout(let command): return String(format: "No reply to 0x%04X.", command)
            case .writeFailed(let reason): return "Sending failed: \(reason)"
            }
        }
    }

    static let gaiaService = CBUUID(string: "00001100-D102-11E1-9B23-00025B00A5A5")
    static let commandCharacteristic = CBUUID(string: "00001101-D102-11E1-9B23-00025B00A5A5")
    static let responseCharacteristic = CBUUID(string: "00001102-D102-11E1-9B23-00025B00A5A5")
    /// Standard Battery Service; its notifications wake the app in the background when a level changes.
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")
    static let nameHints = ["noble", "fokus", "rex5"]
    static let savedPeripheralKey = "rex5.peripheral"
    static let notFoundAfter: Duration = .seconds(30)
    static let pausedKey = "rex5.paused"

    var onState: (@MainActor (State) -> Void)?
    var onDevice: (@MainActor (PairedDevice) -> Void)?
    var onLog: (@MainActor (String) -> Void)?
    var onRestoredConnection: (@MainActor () -> Void)?
    var onBatteryNotification: (@MainActor (UInt8) -> Void)?

    private(set) var state: State = .searching {
        didSet {
            guard state != oldValue else { return }
            stateChange += 1
            onState?(state)
            if state == .connecting || state == .searching { startNotFoundTimer() }
        }
    }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var command: CBCharacteristic?
    private var paused = UserDefaults.standard.bool(forKey: EarbudLink.pausedKey)
    private var stateChange = 0
    private var pendingAck: (id: Int, request: GaiaPacket, continuation: CheckedContinuation<GaiaPacket, Error>)?
    private var nextID = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "homedeck.rex5"])
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAudio() }
        }
    }

    /// True while iOS sends sound to Bluetooth headphones.
    // ponytail: any Bluetooth output counts, since the earbuds' audio name isn't known; match by name if other headphones get in the way.
    static var audioIsUp: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType)
        }
    }

    /// Connect once the audio is up; drop the link if the audio is gone. Call on foreground and audio route changes.
    func checkAudio() {
        if !Self.audioIsUp || state != .ready { connectIfPossible() }
    }

    /// Stop reconnecting after the next drop. Call right before telling the earbuds to drop this iPhone.
    func pauseReconnect() {
        paused = true
        UserDefaults.standard.set(true, forKey: Self.pausedKey)
    }

    /// Clear the pause and connect if the audio is up.
    func resume() {
        paused = false
        UserDefaults.standard.set(false, forKey: Self.pausedKey)
        if state != .ready { connectIfPossible() }
    }

    /// Sends a packet and waits for its acknowledgement.
    func send(_ packet: GaiaPacket, timeout: Duration = .seconds(5)) async throws -> GaiaPacket {
        // ponytail: one request in flight; later callers poll until it clears. Fine for a handful of commands.
        while pendingAck != nil { try await Task.sleep(for: .milliseconds(50)) }
        guard state == .ready, let peripheral, let command else { throw LinkError.notReady }
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pendingAck = (id, packet, continuation)
            write(packet, to: peripheral, command)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                self.finishAck(id: id, .failure(LinkError.timeout(packet.command)))
            }
        }
    }

    /// Sends a packet the earbuds never acknowledge (disconnect, device list) or may not (restore).
    func sendWithoutReply(_ packet: GaiaPacket) throws {
        guard state == .ready, let peripheral, let command else { throw LinkError.notReady }
        write(packet, to: peripheral, command)
    }

    private func write(_ packet: GaiaPacket, to peripheral: CBPeripheral, _ command: CBCharacteristic) {
        let type: CBCharacteristicWriteType = command.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(Data(packet.bytes), for: command, type: type)
    }

    private func connectIfPossible() {
        guard central.state == .poweredOn else { return }
        if paused {
            state = .paused
            return
        }
        guard Self.audioIsUp else {
            central.stopScan()
            if let peripheral, peripheral.state != .disconnected {
                log("No Bluetooth sound, letting go of the earbuds")
                central.cancelPeripheralConnection(peripheral)
            }
            state = .waitingForAudio
            return
        }
        if let peripheral {
            switch peripheral.state {
            case .connected: discover(peripheral)
            case .disconnected:
                state = .connecting
                central.connect(peripheral)
            case .connecting where state == .connecting: break  // our own connect, still going
            default:
                // A connect iOS kept from an earlier run (state restoration) never finishes: the app sat
                // stuck until force-quit, 4 times on 2026-11-11. Start a fresh one, like a clean launch.
                log("Link left \(Self.name(peripheral.state)) by an earlier run; connecting again")
                central.cancelPeripheralConnection(peripheral)
                state = .connecting
                central.connect(peripheral)
            }
            return
        }
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.gaiaService])
        if let known = connected.first(where: { Self.matches($0.name) }) {
            adopt(known)
        } else if let saved = UserDefaults.standard.string(forKey: Self.savedPeripheralKey).flatMap(UUID.init(uuidString:)),
                  let known = central.retrievePeripherals(withIdentifiers: [saved]).first {
            adopt(known)
        } else {
            state = .searching
            central.scanForPeripherals(withServices: nil)
            startNotFoundTimer()  // state may already be .searching, so didSet won't fire
        }
    }

    private func startNotFoundTimer() {
        let mark = stateChange
        Task { @MainActor in
            try? await Task.sleep(for: Self.notFoundAfter)
            if self.stateChange == mark {
                guard Self.audioIsUp else { self.connectIfPossible(); return }  // drop the pending connect
                self.state = .notFound
                if self.peripheral?.state != .connected {
                    self.central.scanForPeripherals(withServices: nil)
                    self.log("Earbuds not found; scanning for them again")
                }
            }
        }
    }

    private func adopt(_ found: CBPeripheral) {
        central.stopScan()
        if let previous = peripheral, previous !== found { central.cancelPeripheralConnection(previous) }
        peripheral = found
        found.delegate = self
        UserDefaults.standard.set(found.identifier.uuidString, forKey: Self.savedPeripheralKey)
        log("Using \(found.name ?? "unnamed earbuds")")
        state = .connecting
        central.connect(found)
    }

    private func discover(_ peripheral: CBPeripheral) {
        command = nil
        peripheral.discoverServices([Self.gaiaService, Self.batteryService])
    }

    private func finishAck(id: Int? = nil, _ result: Result<GaiaPacket, Error>) {
        guard let pending = pendingAck, id == nil || id == pending.id else { return }
        pendingAck = nil
        pending.continuation.resume(with: result)
    }

    private func log(_ text: String) { onLog?(text) }

    static func name(_ state: CBPeripheralState) -> String {
        switch state {
        case .connecting: "connecting"
        case .connected: "connected"
        case .disconnecting: "disconnecting"
        default: "disconnected"
        }
    }

    static func matches(_ name: String?) -> Bool {
        let lower = (name ?? "").lowercased()
        return nameHints.contains { lower.contains($0) }
    }
}

extension EarbudLink: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let managerState = central.state
        MainActor.assumeIsolated {
            switch managerState {
            case .poweredOn: connectIfPossible()
            case .unknown, .resetting: break
            case .poweredOff: state = .bluetoothOff("Bluetooth is off.")
            case .unauthorized: state = .bluetoothOff("Bluetooth access isn't allowed for REX5.")
            default: state = .bluetoothOff("Bluetooth isn't available.")
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first
        MainActor.assumeIsolated {
            guard let restored else { return }
            peripheral = restored
            restored.delegate = self
            log("Relaunched by iOS for Bluetooth (link \(Self.name(restored.state)))")
            if restored.state == .connected { onRestoredConnection?() }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        MainActor.assumeIsolated {
            guard !paused, Self.audioIsUp, self.peripheral?.state != .connected, Self.matches(name) else { return }
            adopt(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            guard peripheral === self.peripheral else { return }
            central.stopScan()
            log("Connected")
            // A leftover pending connect can fire before the audio is up; let go so the audio can connect.
            guard Self.audioIsUp else { connectIfPossible(); return }
            discover(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let reason = error?.localizedDescription ?? "unknown reason"
        MainActor.assumeIsolated {
            guard peripheral === self.peripheral else { return }
            log("Connection failed: \(reason)")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.connectIfPossible()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            guard peripheral === self.peripheral else { return }
            command = nil
            finishAck(.failure(LinkError.notReady))
            log("Disconnected")
            if paused {
                state = .paused
            } else {
                // The audio route can list the earbuds for a moment after they drop, so look again shortly.
                state = .waitingForAudio
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    self.checkAudio()
                }
            }
        }
    }
}

extension EarbudLink: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard peripheral === self.peripheral else { return }
            for service in peripheral.services ?? [] where service.uuid == Self.batteryService {
                peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
            }
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.gaiaService }) else {
                log("The earbuds offer no GAIA service")
                return
            }
            peripheral.discoverCharacteristics([Self.commandCharacteristic, Self.responseCharacteristic], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            guard peripheral === self.peripheral else { return }
            if service.uuid == Self.batteryService {
                for level in service.characteristics ?? [] where level.uuid == Self.batteryLevel {
                    let notifies = level.properties.contains(.notify)
                    if notifies { peripheral.setNotifyValue(true, for: level) }
                    log("Battery service found, " + (notifies ? "subscribing to its updates" : "but it doesn't send updates"))
                }
                return
            }
            guard let command = service.characteristics?.first(where: { $0.uuid == Self.commandCharacteristic }),
                  let response = service.characteristics?.first(where: { $0.uuid == Self.responseCharacteristic })
            else { return }
            self.command = command
            if response.isNotifying { state = .ready } else { peripheral.setNotifyValue(true, for: response) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let reason = error?.localizedDescription
        let notifying = characteristic.isNotifying
        let uuid = characteristic.uuid
        MainActor.assumeIsolated {
            guard peripheral === self.peripheral else { return }
            if let reason {
                log("Notifications for \(uuid) failed: \(reason)")
            } else if notifying && uuid == Self.responseCharacteristic {
                state = .ready
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let reason = error?.localizedDescription
        MainActor.assumeIsolated {
            guard peripheral === self.peripheral, let reason else { return }
            finishAck(.failure(LinkError.writeFailed(reason)))
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let bytes = characteristic.value.map { [UInt8]($0) } ?? []
        let uuid = characteristic.uuid
        MainActor.assumeIsolated {
            guard peripheral === self.peripheral else { return }
            if uuid == Self.batteryLevel {
                if let level = bytes.first { onBatteryNotification?(level) }
                return
            }
            guard let packet = GaiaPacket(bytes: bytes) else { return }
            if let pending = pendingAck, packet.isReply(to: pending.request) {
                finishAck(.success(packet))
            } else if let device = PairedDevice(packet: packet) {
                onDevice?(device)
            } else {
                // ponytail: diagnostic for packets nobody waits for; drop once the EQ replies are understood.
                log(String(format: "Unhandled packet: vendor 0x%04X, command 0x%04X%@, ", packet.vendor, packet.command,
                           packet.isAcknowledgement ? " (ack)" : "") + packet.payload.hex)
            }
        }
    }
}
