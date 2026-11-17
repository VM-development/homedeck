import HubCore
import Network
import SwiftUI
import XiaomiFanKit

/// The fan answers only on the home Wi-Fi: UDP to its IP, encrypted with its token from the owner's Xiaomi account.
/// It never pushes changes, so the screen polls while it is open.
@MainActor
@Observable
final class XiaomiFanDevice: HomeDevice {
    static let id = "xiaomi-fan-2-pro"
    private static let tokenAccount = "xiaomi-fan-2-pro.token"
    private static let ipKey = "xiaomi-fan-2-pro.ip"

    private(set) var status: DeviceStatus = .notSetUp
    private(set) var state: Fan.State?
    /// The last change the fan refused, shown under the controls.
    private(set) var refused: String?
    private(set) var ip: String?
    private var miio: MiIO?

    /// Requests run one at a time.
    @ObservationIgnored private var queue: Task<Void, Never>?
    /// Reads that finish while a write is pending would undo its change on screen; they are dropped.
    @ObservationIgnored private var pendingWrites = 0
    @ObservationIgnored private var lastID = Int.random(in: 1...100_000)
    @ObservationIgnored private let log = ConnectionLog.shared.tagged(XiaomiFanDevice.id)

    init() {
        miio = Keychain.get(Self.tokenAccount).flatMap(MiIO.init(token:))
        ip = UserDefaults.standard.string(forKey: Self.ipKey)
        if isSetUp {
            status = .connecting
            refresh()
        }
    }

    var isSetUp: Bool { miio != nil && ip != nil }

    // MARK: HomeDevice

    func connect() async {}
    func disconnect() async {}
    func makeScreen() -> AnyView { AnyView(XiaomiFanScreen(fan: self)) }

    // MARK: Setup

    /// Returns an error message, or nil when saved.
    func setUp(token: String, ip ipText: String) -> String? {
        guard let miio = MiIO(token: token) else { return "The token is 32 hex characters." }
        let ip = ipText.trimmingCharacters(in: .whitespaces)
        guard IPv4Address(ip) != nil else { return "The IP address looks like 192.168.1.20." }
        Keychain.set(token.filter(\.isHexDigit), for: Self.tokenAccount)
        UserDefaults.standard.set(ip, forKey: Self.ipKey)
        self.miio = miio
        self.ip = ip
        status = .connecting
        log.add("token and IP saved")
        refresh()
        return nil
    }

    func forget() {
        Keychain.set(nil, for: Self.tokenAccount)
        UserDefaults.standard.removeObject(forKey: Self.ipKey)
        miio = nil
        ip = nil
        state = nil
        status = .notSetUp
        log.add("token and IP removed")
    }

    // MARK: Control

    func watch() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    func refresh() {
        enqueue { [self] in
            guard let reply = await call(Fan.read(id: takeID())), isSetUp, pendingWrites == 0 else { return }
            let new = reply.state(updating: state ?? Fan.State())
            if new != state { log.add("state \(Self.describe(new))") }
            state = new
            updateStatus()
        }
    }

    /// Shows the change at once; the read after the write corrects the screen if the fan refused it.
    func set(_ property: Fan.Property, _ value: Any, change: (inout Fan.State) -> Void) {
        guard var shown = state else { return }
        change(&shown)
        state = shown
        updateStatus()
        pendingWrites += 1
        enqueue { [self] in
            let reply = await call(Fan.write(property, value, id: takeID()))
            pendingWrites -= 1
            guard let reply else { return }
            let code = reply.results[property]?.code
            let answer = reply.error ?? "code \(code.map(String.init) ?? "missing")"
            log.add("set \(property.rawValue) = \(value): \(answer)")
            refused = code == 0 ? nil : "The fan refused that change (\(answer))."
        }
        refresh()
    }

    // MARK: Transport

    private func enqueue(_ work: @escaping () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            await work()
        }
    }

    private func takeID() -> Int {
        lastID += 1
        return lastID
    }

    /// A hello for a fresh stamp before every request, as the Xiaomi app does once its stamp is 6 s old.
    /// ponytail: two round trips per request; cache the stamp for 6 s if polling ever feels slow.
    private func call(_ json: Data) async -> Fan.Reply? {
        guard let miio, let ip else { return nil }
        guard let hello = await exchange(MiIO.hello, ip: ip), let header = MiIO.header(hello) else {
            return fail("No answer from the fan at \(ip). The iPhone must be on the same Wi-Fi, the IP must be the fan's, "
                        + "and HomeDeck needs Local Network access (Settings > Privacy & Security > Local Network).")
        }
        guard let packet = await exchange(miio.packet(json: json, did: header.did, stamp: header.stamp &+ 1), ip: ip) else {
            return fail("The fan answered the hello but not the request.")
        }
        guard let body = miio.open(packet), let reply = Fan.Reply(body) else {
            return fail("The fan's reply didn't decrypt: the token is wrong, or it changed when the fan was added to Xiaomi Home again.")
        }
        return reply
    }

    private func fail(_ reason: String) -> Fan.Reply? {
        guard isSetUp else { return nil }  // an answer to a request sent before forget()
        if status != .offline(reason: reason) { log.add(reason) }
        status = .offline(reason: reason)
        return nil
    }

    /// One UDP socket per request with a 2-second wait, like the Xiaomi app.
    private func exchange(_ packet: Data, ip: String) async -> Data? {
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: MiIO.port)!, using: .udp)
        defer { connection.cancel() }
        return await withCheckedContinuation { continuation in
            var done = false
            func finish(_ data: Data?) {
                guard !done else { return }
                done = true
                continuation.resume(returning: data)
            }
            connection.start(queue: .main)
            connection.send(content: packet, completion: .contentProcessed { if $0 != nil { finish(nil) } })
            connection.receiveMessage { data, _, _, _ in finish(data) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { finish(nil) }
        }
    }

    private func updateStatus() {
        guard let state else { return }
        status = .online(summary: state.power ? "On · speed \(state.level)\(state.natural ? " · natural" : "")" : "Off")
    }

    private static func describe(_ s: Fan.State) -> String {
        "power \(s.power), level \(s.level), natural \(s.natural), swing \(s.swing), angle \(s.angle), speed \(s.speed), "
            + "timer \(s.timer), light \(s.light), sound \(s.sound), lock \(s.lock), fault \(s.fault)"
    }
}
