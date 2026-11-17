import Foundation
import PhilipsAirKit

/// Finds the purifier by asking every address on the phone's Wi-Fi subnet for /sys/dev/info, one unicast packet each:
/// Air+ multicasts instead, which an iOS app can only do with Apple's multicast entitlement.
/// ponytail: assumes a /24 home network; read the netmask too if a bigger one ever matters.
enum PurifierFinder {
    static func find() async -> String? {
        await Task.detached { sweep() }.value
    }

    private static func sweep() -> String? {
        guard let own = wifiAddress() else { return nil }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let base = own & 0xFFFF_FF00
        for host in UInt32(1)...254 where base | host != own {
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = CoAP.port.bigEndian
            address.sin_addr.s_addr = (base | host).bigEndian
            let packet = [UInt8](CoAP.request(CoAP.get, id: UInt16(host), token: [0x46, 0x69, 0x6E, 0x64], path: "/sys/dev/info"))
            _ = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        let deadline = Date().addingTimeInterval(4)
        var buffer = [UInt8](repeating: 0, count: 2048)
        while Date() < deadline {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &length) }
            }
            guard count > 0, let message = CoAP.decode(Data(buffer[..<count])),
                  let info = try? JSONSerialization.jsonObject(with: Data(message.payload)) as? [String: Any],
                  (info["type"] as? String)?.hasPrefix("AC2729") == true else { continue }
            return String(cString: inet_ntoa(from.sin_addr))
        }
        return nil
    }

    /// The phone's IPv4 address on Wi-Fi (en0), host byte order.
    private static func wifiAddress() -> UInt32? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var item = list
        while let current = item {
            let interface = current.pointee
            if String(cString: interface.ifa_name) == "en0", interface.ifa_addr.pointee.sa_family == sa_family_t(AF_INET) {
                return interface.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            }
            item = interface.ifa_next
        }
        return nil
    }
}
