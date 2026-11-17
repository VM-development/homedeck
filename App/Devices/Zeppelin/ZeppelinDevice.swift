import CryptoKit
import HubCore
import Network
import SwiftUI
import ZeppelinKit

/// SHA-256 of the speaker's certificate, pinned on first use.
private let certificateKey = "zeppelin-pro.certificate"

/// The Zeppelin Pro speaks the same local JSON API as B&W's own app: queries over HTTPS, changes pushed on a
/// WebSocket. No account. Auto standby lives in a second, plain-HTTP settings API on port 80.
@MainActor
@Observable
final class ZeppelinDevice: HomeDevice {
    static let id = "zeppelin-pro"
    private static let ipKey = "zeppelin-pro.ip"

    private(set) var status: DeviceStatus = .notSetUp
    private(set) var ip: String?
    private(set) var volume: Int?
    /// The volume before muting. The speaker ignores set_volume's "muted" (seen on device), so mute is volume 0.
    private(set) var mutedVolume: Int?
    var muted: Bool { mutedVolume != nil }
    private(set) var bass: Int?
    private(set) var treble: Int?
    private(set) var light: Stated.Light?
    private(set) var nowPlaying: Stated.NowPlaying?
    private(set) var autoStandby: Int?
    private(set) var version: String?
    /// Nil until checked.
    private(set) var update: (available: Bool, version: String)?
    private(set) var problem: String?

    @ObservationIgnored private var node: String?
    @ObservationIgnored private var awaitingVolume = false
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let session = URLSession(configuration: .ephemeral, delegate: SpeakerTrust(), delegateQueue: nil)
    @ObservationIgnored private let log = ConnectionLog.shared.tagged(ZeppelinDevice.id)

    init() {
        ip = UserDefaults.standard.string(forKey: Self.ipKey).map(Self.plain)
        if ip != nil { start() }
    }

    var isSetUp: Bool { ip != nil }

    // MARK: HomeDevice

    func makeScreen() -> AnyView { AnyView(ZeppelinScreen(speaker: self)) }

    // MARK: Setup

    func setUp(ip text: String) -> String? {
        let ip = Self.plain(text.trimmingCharacters(in: .whitespaces))
        guard IPv4Address(ip) != nil else { return "The IP address looks like 192.168.1.20." }
        UserDefaults.standard.set(ip, forKey: Self.ipKey)
        self.ip = ip
        log.add("IP saved")
        start()
        return nil
    }

    /// Without an interface suffix like "%en0", which an address from Network.framework can carry and a URL can't.
    private static func plain(_ ip: String) -> String { ip.components(separatedBy: "%")[0] }

    func forget() {
        loop?.cancel()
        socket?.cancel()
        UserDefaults.standard.removeObject(forKey: Self.ipKey)
        UserDefaults.standard.removeObject(forKey: certificateKey)
        (ip, node, volume, bass, treble, light, nowPlaying, autoStandby, version, update) = (nil, nil, nil, nil, nil, nil, nil, nil, nil, nil)
        status = .notSetUp
        log.add("IP and certificate removed")
    }

    // MARK: Session

    /// Connects, reads everything once, then lives on pushes; starts over 5 s after the WebSocket drops.
    private func start() {
        loop?.cancel()
        status = .connecting
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.session()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func session() async {
        guard let ip else { return }
        guard let data = await get("https://\(ip):\(Stated.port)/mesh/node"),
              let node = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["node_id"] as? String else {
            return fail("No answer from the speaker at \(ip). The iPhone must be on the same Wi-Fi, and HomeDeck needs Local Network "
                        + "access (Settings > Privacy & Security > Local Network). If the speaker was reset, its certificate changed: "
                        + "choose Change speaker.")
        }
        self.node = node
        version = await get("https://\(ip):\(Stated.port)/software/version")
            .flatMap { (try? JSONSerialization.jsonObject(with: $0) as? [String: Any])?["version"] as? String }
        guard let socketURL = URL(string: "wss://\(ip):\(Stated.port)/messages") else { return }
        let socket = session.webSocketTask(with: socketURL)
        self.socket = socket
        socket.resume()
        log.add("connected")
        for property in [Stated.Property.bass, Stated.Property.treble, Stated.Property.light, Stated.Property.nowPlaying] {
            await post(Stated.get(property))
        }
        awaitingVolume = true
        await post(Stated.query("get_volume", ["source": ""]))
        autoStandby = await get(StreamSDK.getURL(ip: ip, path: StreamSDK.autoStandby).absoluteString).flatMap(StreamSDK.int)
        while !Task.isCancelled, let message = try? await socket.receive() {
            switch message {
            case .string(let text): apply(Stated.events(inPush: Data(text.utf8), node: node))
            case .data(let data): apply(Stated.events(inPush: data, node: node))
            @unknown default: break
            }
        }
        socket.cancel()
        if !Task.isCancelled { fail("Lost the connection to the speaker; reconnecting.") }
    }

    private func apply(_ events: [Stated.Event]) {
        for event in events {
            switch event {
            case .volume(let value):
                volume = value
                if value > 0 { mutedVolume = nil }  // raised here or elsewhere
            case .volumeReply(let value):
                if awaitingVolume { volume = value }
                awaitingVolume = false
            case .bass(let value): bass = value
            case .treble(let value): treble = value
            case .light(let value): light = value
            case .nowPlaying(let value):
                if value?.state != nowPlaying?.state || value?.title != nowPlaying?.title {
                    log.add(value.map { "now playing: state \($0.state), \($0.service), actions \($0.actions)" } ?? "nothing playing")
                }
                nowPlaying = value
            case .update(let available, let version):
                update = (available, version)
                log.add("update available: \(available)")
            }
        }
        problem = nil
        updateStatus()
    }

    // MARK: Control

    func setVolume(_ value: Int) {
        volume = value
        send(Stated.setVolume(value, muted: false), "volume \(value)")
    }

    func toggleMute() {
        if let restore = mutedVolume {
            mutedVolume = nil
            setVolume(restore)
        } else if let current = volume, current > 0 {
            mutedVolume = current
            setVolume(0)
        }
    }

    func setBass(_ value: Int) {
        bass = value
        send(Stated.set(Stated.Property.bass, value), "bass \(value)")
    }

    func setTreble(_ value: Int) {
        treble = value
        send(Stated.set(Stated.Property.treble, value), "treble \(value)")
    }

    func setLight(_ value: Stated.Light) {
        light = value
        send(Stated.set(Stated.Property.light, value.json), "light \(value.enabled) \(value.brightness) \(value.red),\(value.green),\(value.blue)")
    }

    func press(_ command: Stated.Command) { send(Stated.send(command), command.rawValue) }

    @ObservationIgnored private var checking = false

    func checkForUpdate() {
        guard !checking else { return }
        checking = true
        Task {
            let ok = await post(Stated.query("check_software_update"))
            log.add("check for update: \(ok ? "ok" : "failed")")
            checking = false
        }
    }

    func installUpdate() { send(Stated.query("start_software_update"), "start update") }

    func setAutoStandby(_ seconds: Int) {
        log.add("auto standby \(seconds) chosen")
        guard let ip else { return }
        autoStandby = seconds
        Task {
            let reply = await get(StreamSDK.setURL(ip: ip, path: StreamSDK.autoStandby, int: seconds).absoluteString)
            log.add("set auto standby \(seconds): \(reply.map { String(decoding: $0, as: UTF8.self).prefix(80) } ?? "no answer")")
            autoStandby = await get(StreamSDK.getURL(ip: ip, path: StreamSDK.autoStandby).absoluteString).flatMap(StreamSDK.int)
        }
    }

    // MARK: Transport

    private func send(_ body: Data, _ description: String) {
        Task {
            let ok = await post(body)
            log.add("set \(description): \(ok ? "ok" : "failed")")
            if !ok { problem = "The speaker didn't take that change." }
        }
    }

    /// Replies that carry a value are applied; the rest arrive on the WebSocket.
    @discardableResult
    private func post(_ body: Data) async -> Bool {
        guard let ip, let node, let url = URL(string: "https://\(ip):\(Stated.port)/mesh/node/\(node)/channel/\(Stated.channel)/message")
        else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        request.timeoutInterval = 5
        guard let (data, response) = try? await session.data(for: request),
              let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return false }
        apply(Stated.events(inReply: data, node: node))
        return true
    }

    private func get(_ url: String) async -> Data? {
        guard let url = URL(string: url) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        return try? await session.data(for: request).0
    }

    private func fail(_ reason: String) {
        guard isSetUp else { return }
        if status != .offline(reason: reason) { log.add(reason) }
        status = .offline(reason: reason)
    }

    private func updateStatus() {
        guard volume != nil else { return }
        let playing = nowPlaying.map { "\($0.state == 1 ? "Playing" : "Paused") · \($0.service)" } ?? "Idle"
        status = .online(summary: "\(playing) · volume \(volume ?? 0)")
    }

    // MARK: Finding the speaker

    /// The speaker advertises `_eva-mesh._tcp`. A UDP "connection" to the service resolves it without needing an
    /// answer, which gives the speaker's IPv4 address.
    static func find() async -> String? {
        await withCheckedContinuation { continuation in
            let browser = NWBrowser(for: .bonjour(type: "_eva-mesh._tcp", domain: nil), using: .tcp)
            var done = false
            func finish(_ ip: String?) {
                guard !done else { return }
                done = true
                browser.cancel()
                continuation.resume(returning: ip)
            }
            browser.browseResultsChangedHandler = { results, _ in
                guard let result = results.first else { return }
                let parameters = NWParameters.udp
                (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
                let connection = NWConnection(to: result.endpoint, using: parameters)
                connection.stateUpdateHandler = { state in
                    guard case .ready = state else { return }
                    if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint, case .ipv4(let address) = host {
                        finish(address.rawValue.map(String.init).joined(separator: "."))
                    }
                    connection.cancel()
                }
                connection.start(queue: .main)
            }
            browser.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { finish(nil) }
        }
    }
}

/// Accepts the speaker's self-signed certificate the first time, and after that only the same certificate.
private final class SpeakerTrust: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else { return (.performDefaultHandling, nil) }
        let fingerprint = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
        let defaults = UserDefaults.standard
        if defaults.string(forKey: certificateKey) == nil { defaults.set(fingerprint, forKey: certificateKey) }
        return defaults.string(forKey: certificateKey) == fingerprint
            ? (.useCredential, URLCredential(trust: trust)) : (.cancelAuthenticationChallenge, nil)
    }
}
