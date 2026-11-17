import CryptoKit
import DreameKit
import HubCore
import SwiftUI

/// A hex-encoded value from Config/Secrets.xcconfig, passed through Info.plist.
private func secret(_ key: String) -> String {
    let hex = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    let bytes = stride(from: 0, to: hex.count - 1, by: 2).compactMap { i -> UInt8? in UInt8(hex.dropFirst(i).prefix(2), radix: 16) }
    return String(decoding: bytes, as: UTF8.self)
}

/// The L40 Ultra has no local API once it's in the Dreamehome app, so HomeDeck signs in to Dreame's cloud with the
/// owner's Dreamehome account and sends MIoT commands through it. Only the session tokens are kept (Keychain).
@MainActor
@Observable
final class DreameDevice: HomeDevice {
    static let id = "dreame-l40-ultra"
    private static let sessionAccount = "dreame-l40-ultra.session"
    static let regions = ["eu": "Europe", "us": "USA", "ru": "Russia", "sg": "Asia", "cn": "China", "kr": "Korea"]

    private(set) var status: DeviceStatus = .notSetUp
    private(set) var model: String?
    /// The latest value of every property that answered.
    private(set) var values: [MIoT: Any] = [:]
    private(set) var problem: String?

    /// Nil when the app was built without the Dreame constants in Config/Secrets.xcconfig.
    let keys = DreameCloud.Keys(salt: secret("DreameSalt"), basic: secret("DreameBasic"), signing: secret("DreameKey"))
    /// The map files' AES IV for this model family.
    let mapIV: String? = { let iv = secret("DreameMapIV"); return iv.count == 16 ? iv : nil }()

    private(set) var map: DreameMap?
    /// From the last map read; cached so room cleaning works without downloading the map again.
    private(set) var rooms: [DreameMap.Room] = []
    private(set) var loadingMap = false

    private static let roomsKey = "dreame-l40-ultra.rooms"

    struct Session: Codable {
        var username: String
        var region: String
        var accessToken: String
        var refreshToken: String
        var expires: Date
        var tenant: String?
        var lang: String?
        var country: String?
        var cloudRegion: String?
        var did: String?
        var host: String?
        var uid: String?
    }

    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var requestID = Int.random(in: 1000...9000)
    @ObservationIgnored private let visitor: String = {
        if let saved = UserDefaults.standard.string(forKey: "dreame-l40-ultra.visitor") { return saved }
        let fresh = Insecure.MD5.hash(data: Data(UUID().uuidString.utf8)).map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(fresh, forKey: "dreame-l40-ultra.visitor")
        return fresh
    }()
    @ObservationIgnored private let http = URLSession(configuration: .ephemeral)
    @ObservationIgnored private let log = ConnectionLog.shared.tagged(DreameDevice.id)

    init() {
        rooms = (UserDefaults.standard.array(forKey: Self.roomsKey) as? [[String: Any]] ?? []).compactMap {
            guard let id = $0["id"] as? Int, let name = $0["name"] as? String else { return nil }
            return DreameMap.Room(id: id, name: name, type: $0["type"] as? Int ?? 0)
        }
        session = Keychain.get(Self.sessionAccount).flatMap { try? JSONDecoder().decode(Session.self, from: Data($0.utf8)) }
        if session != nil {
            status = .connecting
            Task { await refresh() }
        }
    }

    var isSetUp: Bool { session != nil }

    // MARK: HomeDevice

    func connect() async {}
    func disconnect() async {}
    func makeScreen() -> AnyView { AnyView(DreameScreen(robot: self)) }

    // MARK: Sign-in

    /// Returns an error message, or nil when signed in and the robot was found.
    func signIn(username: String, password: String, region: String) async -> String? {
        guard let keys else { return "This build of HomeDeck has no Dreame constants (Config/Secrets.xcconfig)." }
        let user = username.trimmingCharacters(in: .whitespaces)
        var probe = Session(username: user, region: region, accessToken: "", refreshToken: "", expires: .distantPast)
        guard let reply = await token(DreameCloud.loginForm(username: user, password: password, keys: keys), for: probe) else {
            return problem ?? "Sign-in failed."
        }
        probe = reply
        session = probe
        guard await findRobot() else { return problem ?? "No Dreame robot in this account." }
        save()
        log.add("signed in, robot \(model ?? "?")")
        await probeEverything()
        return nil
    }

    func signOut() {
        Keychain.set(nil, for: Self.sessionAccount)
        session = nil
        model = nil
        values = [:]
        status = .notSetUp
        log.add("signed out")
    }

    private func token(_ form: String, for current: Session) async -> Session? {
        guard keys != nil, let url = URL(string: DreameCloud.baseURL(region: current.region) + "/dreame-auth/oauth/token") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = Data(form.utf8)
        headers(for: current, contentType: "application/x-www-form-urlencoded").forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        guard let (data, response) = try? await http.data(for: request), let code = (response as? HTTPURLResponse)?.statusCode else {
            problem = "No answer from Dreame's \(Self.regions[current.region] ?? current.region) server."
            return nil
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard code == 200, let access = object["access_token"] as? String, let refresh = object["refresh_token"] as? String else {
            let reason = object["error_description"] as? String ?? object["msg"] as? String ?? "HTTP \(code)"
            log.add("sign-in refused: \(code) \(reason)")
            problem = "Dreame refused the sign-in (\(reason)). Use the Dreamehome password (set one in the app if you sign in with Google or Apple), and the region your account is in."
            return nil
        }
        var next = current
        next.accessToken = access
        next.refreshToken = refresh
        next.expires = Date().addingTimeInterval(TimeInterval(object["expires_in"] as? Int ?? 3600))
        next.tenant = object["tenant_id"] as? String ?? next.tenant
        next.lang = object["lang"] as? String ?? next.lang
        next.country = object["country"] as? String ?? next.country
        next.cloudRegion = object["region"] as? String ?? next.cloudRegion
        return next
    }

    private func headers(for session: Session, contentType: String) -> [String: String] {
        guard let keys else { return [:] }
        var h = ["User-Agent": DreameCloud.userAgent, "dreame-meta": DreameCloud.meta(username: session.username, visitor: visitor),
                 "tenant-id": session.tenant ?? "000000", "authorization": "Basic \(keys.basic)", "content-type": contentType]
        if let region = session.cloudRegion, let lang = session.lang, let country = session.country {
            h["dreame-rlc"] = DreameCloud.rlc(region: region, lang: lang, country: country, keys: keys)
        }
        if !session.accessToken.isEmpty { h["dreame-auth"] = session.accessToken }
        return h
    }

    private func save() {
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        Keychain.set(String(decoding: data, as: UTF8.self), for: Self.sessionAccount)
    }

    // MARK: Cloud calls

    /// POSTs signed JSON to a cloud path; returns the reply's `data`. Refreshes the token when it's close to expiring.
    private func api(_ path: String, _ params: [String: Any]?, timeout: TimeInterval = 10) async -> Any? {
        guard var current = session, let keys else { return nil }
        if current.expires.timeIntervalSinceNow < 600 {
            guard let renewed = await token(DreameCloud.refreshForm(current.refreshToken), for: current) else {
                status = .offline(reason: problem ?? "The Dreame session ended; sign in again.")
                return nil
            }
            current = renewed
            session = renewed
            save()
            log.add("session refreshed")
        }
        guard let url = URL(string: DreameCloud.baseURL(region: current.region) + "/" + path) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        if let params {
            let body = DreameCloud.signed(params, milliseconds: Int64(Date().timeIntervalSince1970 * 1000), keys: keys)
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        headers(for: current, contentType: "application/json").forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        guard let (data, response) = try? await http.data(for: request), let code = (response as? HTTPURLResponse)?.statusCode else {
            fail("No answer from Dreame's cloud. Check the iPhone's internet connection.")
            return nil
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard code == 200, object["code"] as? Int == 0 else {
            let reason = "\(code) \(object["code"].map { "\($0)" } ?? "") \(object["msg"] as? String ?? "")"
            log.add("\(path.split(separator: "/").last ?? ""): \(reason)")
            if object["code"] as? Int == 80001 { fail("The robot isn't answering Dreame's cloud (offline or asleep).") }
            return nil
        }
        return object["data"]
    }

    private func findRobot() async -> Bool {
        guard let data = await api("dreame-user-iot/iotuserbind/device/listV2", nil) as? [String: Any],
              let records = (data["page"] as? [String: Any])?["records"] as? [[String: Any]] else { return false }
        let robots = records.filter { ($0["model"] as? String)?.contains(".vacuum.") == true }
        log.add("devices: \(records.count), robots: \(robots.compactMap { $0["model"] as? String })")
        guard let robot = robots.first, let did = robot["did"] as? String ?? (robot["did"] as? Int).map(String.init) else {
            problem = "No Dreame robot in this account."
            return false
        }
        session?.did = did
        model = robot["model"] as? String
        if let info = await api("dreame-user-iot/iotuserbind/device/info", ["did": did]) as? [String: Any] {
            session?.host = info["bindDomain"] as? String
            session?.uid = (info["masterUid"] as? String) ?? (info["masterUid"] as? Int).map(String.init)
            model = info["model"] as? String ?? model
        }
        log.add("robot \(model ?? "?"), host \(session?.host == nil ? "missing" : "found")")
        return session?.host != nil
    }

    /// One MIoT call through the cloud; `result` of the reply. The cloud holds the request while it waits for the robot.
    private func send(_ method: String, _ params: Any) async -> Any? {
        guard let did = session?.did, let host = session?.host else { return nil }
        requestID += 1
        let path = "dreame-iot-com-\(host.split(separator: ".").first ?? "")/device/sendCommand"
        let data = await api(path, DreameCloud.command(did: did, id: requestID, method: method, params: params), timeout: 20)
        return (data as? [String: Any])?["result"]
    }

    func read(_ props: [MIoT]) async -> [MIoT: Any] {
        guard let did = session?.did else { return [:] }
        var out: [MIoT: Any] = [:]
        for batch in stride(from: 0, to: props.count, by: 10).map({ Array(props[$0..<min($0 + 10, props.count)]) }) {
            out.merge(MIoT.values(await send("get_properties", MIoT.getProperties(batch, did: did)))) { $1 }
        }
        return out
    }

    // MARK: State

    static let core = [MIoT(2, 1), MIoT(2, 2), MIoT(3, 1), MIoT(3, 2), MIoT(4, 1), MIoT(4, 2), MIoT(4, 3), MIoT(4, 4), MIoT(4, 7),
                       MIoT(4, 23), MIoT(4, 25), MIoT(4, 63), MIoT(15, 5), MIoT(28, 1)]

    /// Candidates from Tasshack's and Valetudo's tables; no spec exists for this model, so the log shows what answers.
    static let candidates = core + [
        MIoT(4, 5), MIoT(4, 10), MIoT(4, 11), MIoT(4, 12), MIoT(4, 18), MIoT(4, 27), MIoT(4, 28), MIoT(4, 37), MIoT(4, 40), MIoT(4, 46),
        MIoT(5, 1), MIoT(5, 2), MIoT(5, 3), MIoT(6, 3), MIoT(7, 1), MIoT(8, 1),
        MIoT(9, 1), MIoT(9, 2), MIoT(10, 1), MIoT(10, 2), MIoT(11, 1), MIoT(11, 2), MIoT(12, 1), MIoT(12, 2), MIoT(12, 3), MIoT(12, 4),
        MIoT(15, 1), MIoT(15, 2), MIoT(16, 1), MIoT(16, 2), MIoT(17, 1), MIoT(17, 2), MIoT(18, 1), MIoT(18, 2),
        MIoT(27, 1), MIoT(27, 2), MIoT(27, 3), MIoT(27, 4), MIoT(30, 1), MIoT(30, 2), MIoT(32, 1), MIoT(32, 2),
    ]

    private func probeEverything() async {
        let found = await read(Self.candidates)
        values.merge(found) { $1 }
        let missing = Self.candidates.filter { found[$0] == nil }
        let shown = found.keys.sorted { ($0.siid, $0.piid) < ($1.siid, $1.piid) }.map { key -> String in
            let value = found[key]!
            if let text = value as? String, text.count > 24 { return "\(key)=<text \(text.count)>" }
            return "\(key)=\(value)"
        }
        log.add("probe: \(shown.joined(separator: " "))")
        log.add("probe: no answer from \(missing.map(\.description).joined(separator: " "))")
        updateStatus()
    }

    func refresh(full: Bool = false) async {
        if session?.host == nil || model == nil { guard await findRobot() else { return } }
        values.merge(await read(full ? Self.candidates : Self.core)) { $1 }
        updateStatus()
    }

    /// Everything once when the screen opens, then the moving parts every 5 s.
    func watch() async {
        await refresh(full: true)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            await refresh()
        }
    }

    // MARK: Control

    /// Shows the new value at once; the next read corrects it if the robot didn't take it.
    func set(_ prop: MIoT, _ value: Any, _ description: String) {
        guard let did = session?.did else { return }
        values[prop] = value
        Task {
            let result = await send("set_properties", MIoT.setProperty(prop, value, did: did))
            let code = ((result as? [[String: Any]])?.first?["code"] as? Int)
            log.add("set \(description) (\(prop)=\(value)): \(code.map { "code \($0)" } ?? "no answer")")
            problem = code == 0 ? nil : "The robot didn't take that change."
        }
    }

    func act(_ action: MIoT, _ description: String, in parameters: [(piid: Int, value: Any)] = []) {
        guard let did = session?.did else { return }
        Task {
            let result = await send("action", MIoT.action(action, did: did, in: parameters))
            let code = (result as? [String: Any])?["code"] as? Int
            log.add("\(description) (action \(action)): \(code.map { "code \($0)" } ?? "no answer")")
            problem = code == 0 ? nil : "The robot didn't do that."
            try? await Task.sleep(for: .seconds(2))
            await refresh()
        }
    }

    /// 4.23 packs the cleaning mode (byte 0), the mop-wash interval (byte 1) and more (byte 2). Mop-lifting robots
    /// swap 0 and 2: raw 0 = vacuum and mop, 2 = vacuum only (Tasshack's split_group_value).
    var cleaningMode: Int? { int(MIoT(4, 23)).map { $0 & 0x03 } }

    /// Tasshack's split_group_value and combine_group_value, kept literally (the masks look odd but match his robots).
    static func withMode(_ packed: Int, _ mode: Int) -> Int {
        ((((packed >> 16) << 8) ^ ((packed >> 8) & ~0x300)) << 8) ^ mode
    }

    func setCleaningMode(_ raw: Int) {
        guard let packed = int(MIoT(4, 23)) else { return }
        set(MIoT(4, 23), Self.withMode(packed, raw), "cleaning mode \(raw)")
    }

    // MARK: Map and rooms

    /// Asks the robot for a full map frame (action 6.1). The answer names a file in Dreame's storage, or carries the
    /// map itself; the file comes through a short-lived download link.
    func loadMap() async {
        guard let did = session?.did, !loadingMap else { return }
        loadingMap = true
        defer { loadingMap = false }
        let request = #"{"req_type":1,"frame_type":"I","force_type":1}"#
        let result = await send("action", MIoT.action(MIoT(6, 1), did: did, in: [(2, request)])) as? [String: Any]
        let out = result?["out"] as? [[String: Any]] ?? []
        log.add("map request: code \(result?["code"].map { "\($0)" } ?? "none"), out "
                + out.map { "\($0["piid"] ?? "?")=\(($0["value"] as? String)?.count ?? -1)ch" }.joined(separator: " "))
        var text: String?
        var file: String?
        var key: String?
        for entry in out {
            guard let value = entry["value"] as? String, !value.isEmpty else { continue }
            switch entry["piid"] as? Int {
            case 3:
                let parts = value.split(separator: ",", maxSplits: 1).map(String.init)
                (file, key) = (parts[0], parts.count > 1 ? parts[1] : nil)
            case 1: text = value
            case 13 where file == nil && text == nil:  // older robots: "0,<map>" or "1,<file>[,<key>]"
                let parts = value.split(separator: ",").map(String.init)
                if parts.first == "0", parts.count > 1 { text = parts[1] }
                if parts.first == "1", parts.count > 1 { (file, key) = (parts[1], parts.count > 2 ? parts[2] : nil) }
            default: break
            }
        }
        if text == nil, let file { text = await download(file) }
        guard let text else { return fail("The robot didn't send a map.") }
        guard let decoded = DreameMap(text: text, key: key, iv: mapIV) else {
            log.add("map didn't decode (\(text.count) chars, key \(key == nil ? "none" : "given"), IV \(mapIV == nil ? "missing" : "set"))")
            return fail("The map didn't decode.")
        }
        map = decoded
        if !decoded.allRooms.isEmpty {
            rooms = decoded.allRooms
            UserDefaults.standard.set(rooms.map { ["id": $0.id, "name": $0.name, "type": $0.type] }, forKey: Self.roomsKey)
        }
        var low: [Int: Int] = [:]
        var high: [Int: Int] = [:]
        for p in decoded.pixels where p != 0 {
            low[Int(p & 0x3F), default: 0] += 1
            high[Int(p >> 6), default: 0] += 1
        }
        log.add("map: frame \(decoded.frameType) \(decoded.width)x\(decoded.height) grid \(decoded.gridSize), json \(decoded.json.keys.sorted())")
        if let saved = decoded.savedMap {
            log.add("saved map: frame \(saved.frameType) \(saved.width)x\(saved.height), json \(saved.json.keys.sorted()), rooms \(saved.rooms.map { "\($0.id) type \($0.type)" })")
        }
        log.add("map rooms: \(decoded.allRooms.map { "\($0.id) type \($0.type)" }); pixels low6 \(low.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }) high2 \(high.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" })")
    }

    private func download(_ file: String) async -> String? {
        guard let session, let did = session.did, let model else { return nil }
        var link = await api("dreame-user-iot/iotfile/getDownloadUrl", ["did": did, "model": model, "filename": file, "region": session.region]) as? String
        if link == nil, let uid = session.uid {
            link = await api("dreame-user-iot/iotfile/getOss1dDownloadUrl",
                             ["did": did, "uid": uid, "model": model, "filename": String(file.dropFirst()), "region": session.region]) as? String
        }
        log.add("map file link: \(link == nil ? "none" : "ok")")
        guard let link, let url = URL(string: link), let (data, _) = try? await http.data(from: url) else { return nil }
        log.add("map file: \(data.count) bytes")
        return String(decoding: data, as: UTF8.self)
    }

    /// Room cleaning (mode 18) with the robot's current suction and water for each room, once, in Dreame's 5th-gen order.
    func clean(rooms ids: [Int]) {
        let suction = int(MIoT(4, 4)) ?? 1
        let water = int(MIoT(4, 5)) ?? 2
        let selects = ids.map { [$0, 1, suction, water, 1] }
        guard let data = try? JSONSerialization.data(withJSONObject: ["selects": selects]) else { return }
        act(MIoT(4, 1), "clean rooms \(ids)", in: [(1, 18), (10, String(decoding: data, as: UTF8.self))])
    }

    func int(_ prop: MIoT) -> Int? { (values[prop] as? NSNumber)?.intValue }
    func text(_ prop: MIoT) -> String? { values[prop] as? String }

    /// Some on/off properties are JSON booleans, others 0/1; a write uses the type the robot reported.
    func setFlag(_ prop: MIoT, _ on: Bool, _ description: String) {
        let isBool = (values[prop] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        set(prop, isBool ? on as Any : (on ? 1 : 0) as Any, description)
    }

    private func fail(_ reason: String) {
        if status != .offline(reason: reason) { log.add(reason) }
        status = .offline(reason: reason)
    }

    private func updateStatus() {
        guard let battery = int(MIoT(3, 1)) else { return }
        problem = nil
        status = .online(summary: "\(Self.stateName(int(MIoT(2, 1)))) · \(battery) %")
    }

    /// Tasshack's state list (2.1), the common values.
    static func stateName(_ state: Int?) -> String {
        switch state {
        case 1: "Cleaning"
        case 2: "Idle"
        case 3: "Paused"
        case 4: "Error"
        case 5: "Returning"
        case 6: "Charging"
        case 7: "Mopping"
        case 8: "Drying the mops"
        case 9: "Washing the mops"
        case 10: "Returning to wash"
        case 11: "Building a map"
        case 13: "Charged"
        case nil: "Unknown"
        default: "State \(state!)"
        }
    }
}
