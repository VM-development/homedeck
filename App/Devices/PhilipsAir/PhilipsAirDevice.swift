import HubCore
import Network
import PhilipsAirKit
import SwiftUI

/// The purifier speaks encrypted CoAP on the home Wi-Fi. HomeDeck keeps one UDP socket open while the app runs,
/// syncs a message counter, then observes /sys/dev/status: the purifier pushes its whole state on every change.
@MainActor
@Observable
final class PhilipsAirDevice: HomeDevice {
    static let id = "philips-ac2729"
    private static let ipKey = "philips-ac2729.ip"
    /// The purifier keeps a few status subscriptions and stops answering when they fill up; an app that iOS kills
    /// can't cancel its own. Re-registering from the same port with the same token replaces the old one instead
    /// (seen on device: five registrations in a row without cancelling, still answered).
    private static let localPort: NWEndpoint.Port = 56830
    private static let observeToken = Array("HDck".utf8)

    private(set) var status: DeviceStatus = .notSetUp
    private(set) var state: Purifier.State?
    /// The last change the purifier refused, shown under the controls.
    private(set) var refused: String?
    private(set) var ip: String?
    /// Nil when the app was built without Config/Secrets.xcconfig.
    let cipher = LANCipher(secret: Bundle.main.object(forInfoDictionaryKey: "PhilipsLANSecret") as? String ?? "")

    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private var messageID = UInt16.random(in: 0...UInt16.max)
    @ObservationIgnored private var waiting: [[UInt8]: CheckedContinuation<CoAP.Message?, Never>] = [:]
    @ObservationIgnored private var observing = false
    @ObservationIgnored private var lastPush: Date?
    @ObservationIgnored private var maxAge: TimeInterval = 60
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var pendingWrites = 0
    @ObservationIgnored private let log = ConnectionLog.shared.tagged(PhilipsAirDevice.id)

    init() {
        ip = UserDefaults.standard.string(forKey: Self.ipKey)
        if isSetUp { start() }
    }

    var isSetUp: Bool { ip != nil }

    // MARK: HomeDevice

    func makeScreen() -> AnyView { AnyView(PhilipsAirScreen(purifier: self)) }

    // MARK: Setup

    func setUp(ip ipText: String) -> String? {
        let ip = ipText.trimmingCharacters(in: .whitespaces)
        guard IPv4Address(ip) != nil else { return "The IP address looks like 192.168.1.20." }
        UserDefaults.standard.set(ip, forKey: Self.ipKey)
        self.ip = ip
        log.add("IP saved")
        start()
        return nil
    }

    func forget() {
        stop()
        UserDefaults.standard.removeObject(forKey: Self.ipKey)
        ip = nil
        state = nil
        status = .notSetUp
        log.add("IP removed")
    }

    // MARK: Session

    /// Registers for pushes, and registers again when they stop: a restart or a lost packet ends the observation.
    private func start() {
        guard cipher != nil else {
            status = .offline(reason: "This build of HomeDeck has no Philips LAN secret (Config/Secrets.xcconfig).")
            return
        }
        stop()
        status = .connecting
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let quiet = self.lastPush.map { Date().timeIntervalSince($0) } ?? .infinity
                if quiet > 3 * self.maxAge { await self.observe() }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func stop() {
        if observing, let connection {  // Observe 1 cancels the subscription
            connection.send(content: CoAP.request(CoAP.get, id: messageID &+ 1, token: Self.observeToken, path: "/sys/dev/status",
                                                  observe: true, observeValue: 1), completion: .contentProcessed { _ in })
        }
        loop?.cancel()
        loop = nil
        connection?.cancel()
        connection = nil
        observing = false
        lastPush = nil
        for (_, continuation) in waiting { continuation.resume(returning: nil) }
        waiting = [:]
    }

    private func observe() async {
        guard await sync() != nil else { return }
        observing = true
        // The reply to the registration is the first push; it took 3-10 s on device.
        if await request(CoAP.get, path: "/sys/dev/status", token: Self.observeToken, observe: true, wait: 20) == nil {
            fail("The purifier answers but sends no status. Close Air+ on other phones and wait a minute.")
        }
    }

    /// The purifier's counter, which the next command continues from. Synced before every command, as Air+ seems to
    /// (it throttles syncs to one per 600 ms). ponytail: one extra round trip per command on the LAN.
    private func sync() async -> UInt32? {
        let mine = String(format: "%08X", UInt32.random(in: 1...2_000_000_000))
        guard let reply = await request(CoAP.post, path: "/sys/dev/sync", payload: Array(mine.utf8), wait: 5),
              let value = UInt32(String(decoding: reply.payload, as: UTF8.self), radix: 16) else {
            fail("No answer from the purifier at \(ip ?? "?"). The iPhone must be on the same Wi-Fi, the IP must be the "
                 + "purifier's, and HomeDeck needs Local Network access (Settings > Privacy & Security > Local Network).")
            return nil
        }
        return value
    }

    // MARK: Control

    /// Shows the change at once; the purifier's next push corrects the screen if it didn't take.
    func send(_ pairs: [String: Any], change: (inout Purifier.State) -> Void) {
        guard var shown = state, let cipher else { return }
        change(&shown)
        state = shown
        updateStatus()
        pendingWrites += 1
        let body = Purifier.command(pairs)
        let description = pairs.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        let previous = queue
        queue = Task {
            await previous?.value
            var answer = "no answer"
            for _ in 1...2 {  // the open-source clients re-sync and retry on "failed"
                guard let synced = await sync() else { break }
                let next = LANCipher.next(synced)
                let payload = Array(cipher.seal(body, counter: next).utf8)
                guard let reply = await request(CoAP.post, path: "/sys/dev/control", payload: payload, wait: 5) else { continue }
                answer = String(decoding: reply.payload, as: UTF8.self)
                if answer.contains("success") { break }
            }
            pendingWrites -= 1
            log.add("set \(description): \(answer)")
            refused = answer.contains("success") ? nil : "The purifier didn't take that change (\(answer))."
        }
    }

    // MARK: Transport

    private func request(_ code: UInt8, path: String, token: [UInt8]? = nil, observe: Bool = false,
                         payload: [UInt8] = [], wait seconds: Double) async -> CoAP.Message? {
        guard let connection = open() else { return nil }
        let token = token ?? randomToken()
        messageID &+= 1
        let packet = CoAP.request(code, id: messageID, token: token, path: path, observe: observe, payload: payload)
        return await withCheckedContinuation { continuation in
            waiting[token] = continuation
            connection.send(content: packet, completion: .contentProcessed { _ in })
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                waiting.removeValue(forKey: token)?.resume(returning: nil)
            }
        }
    }

    private func open() -> NWConnection? {
        if let connection { return connection }
        guard let ip else { return nil }
        let parameters = NWParameters.udp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.any), port: Self.localPort)
        parameters.allowLocalEndpointReuse = true
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: CoAP.port)!, using: parameters)
        self.connection = connection
        connection.start(queue: .main)
        receive(on: connection)
        return connection
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            MainActor.assumeIsolated {
                guard let self, self.connection === connection else { return }
                if let data, let message = CoAP.decode(data) { self.handle(message) }
                if error == nil { self.receive(on: connection) }
            }
        }
    }

    private func handle(_ message: CoAP.Message) {
        if message.kind == .confirmable { connection?.send(content: CoAP.ack(id: message.id), completion: .contentProcessed { _ in }) }
        if observing, message.token == Self.observeToken { push(message) }
        waiting.removeValue(forKey: message.token)?.resume(returning: message)
    }

    private func push(_ message: CoAP.Message) {
        guard let cipher, let opened = cipher.open(String(decoding: message.payload, as: UTF8.self)) else {
            log.add("push didn't decrypt (\(message.codeText), \(message.payload.count) bytes)")
            return
        }
        lastPush = Date()
        if let age = message.uint(CoAP.Option.maxAge) { maxAge = TimeInterval(max(age, 10)) }
        guard pendingWrites == 0, let new = Purifier.State(json: opened.plaintext, previous: state ?? Purifier.State()) else { return }
        if new != state { log.add("state \(Self.describe(new))") }
        state = new
        updateStatus()
    }

    private func fail(_ reason: String) {
        guard isSetUp else { return }
        if status != .offline(reason: reason) { log.add(reason) }
        status = .offline(reason: reason)
    }

    private func randomToken() -> [UInt8] { (0..<4).map { _ in UInt8.random(in: 0...255) } }

    private func updateStatus() {
        guard let state else { return }
        status = .online(summary: state.power ? "On · \(Self.modeName(state))\(state.pm25.map { " · PM2.5 \($0)" } ?? "")" : "Off")
    }

    static func modeName(_ s: Purifier.State) -> String {
        switch s.mode {
        case "P": "Auto"
        case "A": "Allergen"
        case "S": "Sleep"
        default: s.fanSpeed == "t" ? "Turbo" : "Speed \(s.fanSpeed)"
        }
    }

    private static func describe(_ s: Purifier.State) -> String {
        "power \(s.power), mode \(s.mode), om \(s.fanSpeed), humidify \(s.humidify), rhset \(s.humidityTarget), rh \(s.humidity ?? -1), "
            + "temp \(s.temperature ?? -1), pm25 \(s.pm25 ?? -1), iaql \(s.allergenIndex ?? -1), aqil \(s.brightness), cl \(s.childLock), "
            + "dt \(s.timer), dtrs \(s.timerLeft ?? -1), err \(s.error), wl \(s.waterLevel ?? -1), "
            + "filters \(s.preFilter ?? -1)/\(s.hepa ?? -1)/\(s.carbon ?? -1)/\(s.wick ?? -1)"
    }
}

extension PhilipsAirDevice: PowerSwitchable {
    var isOn: Bool? { state?.power }
    func setPower(_ on: Bool) { send(["pwr": on ? "1" : "0"]) { $0.power = on } }
}
