import CommonCrypto
import CryptoKit
import Foundation

/// The Dreamehome cloud, as the Dreamehome app (2.6.7.0) uses it. Dreame robots bound to Dreamehome switch off
/// their local API, so every command goes through `https://<region>.iot.dreame.tech:13267`.
/// The app's fixed constants (password salt, client blob, signing key) are not in the repo: HomeDeck reads them
/// from the git-ignored Config/Secrets.xcconfig, and the tests use made-up ones.
public enum DreameCloud {
    public static let appVersion = "102060700"  // versionCode of Dreamehome 2.6.7.0
    public static let userAgent = "Dart/3.9 (dart:io)"

    public struct Keys {
        public let salt, basic, signing: String

        public init?(salt: String, basic: String, signing: String) {
            guard !salt.isEmpty, !basic.isEmpty, signing.utf8.count == 16 else { return nil }
            (self.salt, self.basic, self.signing) = (salt, basic, signing)
        }
    }

    public static func baseURL(region: String) -> String { "https://\(region).iot.dreame.tech:13267" }

    // MARK: Sign-in

    public static func passwordHash(_ password: String, salt: String) -> String { md5(password + salt) }

    public static func loginForm(username: String, password: String, keys: Keys) -> String {
        let user = username.addingPercentEncoding(withAllowedCharacters: unreserved) ?? username
        return "grant_type=password&scope=all&platform=ANDROID&type=account&username=\(user)&password=\(passwordHash(password, salt: keys.salt))"
    }

    /// ASCII letters, digits and -._~, like Python's quote(safe="").
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func refreshForm(_ refreshToken: String) -> String {
        "grant_type=refresh_token&scope=all&platform=ANDROID&type=account&refresh_token=\(refreshToken)"
    }

    /// What the app adds to every request: its version and three browser-style hashes.
    public static func meta(username: String, visitor: String) -> String {
        "cv=a_\(appVersion);canvasHash=\(md5(username + "c").prefix(8));webglHash=\(md5(username + "w").prefix(8));visitorIdHash=\(visitor)"
    }

    /// The `dreame-rlc` header: AES-128-ECB of "region|lang|country" under the signing key, base64.
    public static func rlc(region: String, lang: String, country: String, keys: Keys) -> String? {
        let input = Array("\(region)|\(lang)|\(country)".utf8)
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var written = 0
        let key = Array(keys.signing.utf8)
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                             key, key.count, nil, input, input.count, &output, output.count, &written)
        return status == kCCSuccess ? Data(output.prefix(written)).base64EncodedString() : nil
    }

    // MARK: Signed requests

    /// Keys sorted; a nested object becomes `k=[…]` (`k=]` when empty) with JSON-quoted scalars and no lists;
    /// a top-level list is compact JSON; booleans are true/false; top-level scalars are plain.
    public static func canonical(_ object: [String: Any], top: Bool = true) -> String {
        object.keys.sorted().compactMap { key -> String? in
            let value = object[key]!
            switch value {
            case let nested as [String: Any]:
                let inner = canonical(nested, top: false)
                return inner.isEmpty ? "\(key)=]" : "\(key)=[\(inner)]"
            case let list as [Any]:
                guard top, let data = try? JSONSerialization.data(withJSONObject: list, options: [.sortedKeys, .withoutEscapingSlashes])
                else { return nil }
                return "\(key)=\(String(decoding: data, as: UTF8.self))"
            case let flag as Bool: return "\(key)=\(flag)"
            case is NSNull: return "\(key)=null"
            case let text as String: return top ? "\(key)=\(text)" : "\(key)=\"\(text)\""
            default: return "\(key)=\(value)"
            }
        }.joined(separator: "&")
    }

    /// The body with `sign` (MD5 of canonical + milliseconds + key) and `timestamp` added.
    public static func signed(_ params: [String: Any], milliseconds: Int64, keys: Keys) -> [String: Any] {
        var out = params
        out["sign"] = md5(canonical(params) + "\(milliseconds)" + keys.signing)
        out["timestamp"] = milliseconds
        return out
    }

    /// Any MIoT call (get_properties, set_properties, action) for /dreame-iot-com-<host>/device/sendCommand.
    public static func command(did: String, id: Int, method: String, params: Any) -> [String: Any] {
        ["did": did, "id": id, "data": ["did": did, "id": id, "method": method, "params": params]]
    }

    static func md5(_ text: String) -> String { Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}

/// MIoT addresses: a property is service.property, an action service.action.
public struct MIoT: Hashable, CustomStringConvertible {
    public let siid, piid: Int
    public init(_ siid: Int, _ piid: Int) { (self.siid, self.piid) = (siid, piid) }
    public var description: String { "\(siid).\(piid)" }

    public static func getProperties(_ props: [MIoT], did: String) -> [[String: Any]] {
        props.map { ["did": did, "siid": $0.siid, "piid": $0.piid] }
    }

    public static func setProperty(_ prop: MIoT, _ value: Any, did: String) -> [[String: Any]] {
        [["did": did, "siid": prop.siid, "piid": prop.piid, "value": value]]
    }

    public static func action(_ action: MIoT, did: String, in parameters: [(piid: Int, value: Any)] = []) -> [String: Any] {
        ["did": did, "siid": action.siid, "aiid": action.piid, "in": parameters.map { ["piid": $0.piid, "value": $0.value] }]
    }

    /// `result` of get_properties: values for the entries with code 0.
    public static func values(_ result: Any?) -> [MIoT: Any] {
        var out: [MIoT: Any] = [:]
        for entry in result as? [[String: Any]] ?? [] {
            guard let s = entry["siid"] as? Int, let p = entry["piid"] as? Int, (entry["code"] as? Int ?? 0) == 0,
                  let value = entry["value"] else { continue }
            out[MIoT(s, p)] = value
        }
        return out
    }
}
