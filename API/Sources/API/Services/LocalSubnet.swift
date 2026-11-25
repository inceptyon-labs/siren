import Darwin
import Foundation

/// The /24 networks this device is on, from its Wi-Fi and wired IPv4 addresses.
enum LocalSubnet {
  /// "192.168.2" for a device at 192.168.2.40.
  static func prefixes() -> [String] {
    var addresses: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addresses) == 0, let first = addresses else { return [] }
    defer { freeifaddrs(addresses) }

    var prefixes: [String] = []
    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let interface = pointer.pointee
      // en* is Wi-Fi and Ethernet; cellular (pdp_ip*) and VPN (utun*) are skipped.
      guard String(cString: interface.ifa_name).hasPrefix("en"),
        let address = interface.ifa_addr,
        address.pointee.sa_family == UInt8(AF_INET)
      else { continue }

      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      guard
        getnameinfo(
          address,
          socklen_t(address.pointee.sa_len),
          &host,
          socklen_t(host.count),
          nil,
          0,
          NI_NUMERICHOST
        ) == 0
      else { continue }

      let octets = String(cString: host).split(separator: ".")
      guard octets.count == 4 else { continue }
      let prefix = octets.prefix(3).joined(separator: ".")
      if !prefixes.contains(prefix) { prefixes.append(prefix) }
    }
    return prefixes
  }
}
