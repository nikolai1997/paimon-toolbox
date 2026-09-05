import Foundation
import Darwin

struct DirectDeskDevice: Decodable, Identifiable, Equatable {
    let deviceID: String
    let name: String
    let status: String
    var host: String
    var id: String { deviceID }

    enum CodingKeys: String, CodingKey { case deviceID = "device_id", name, status }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try values.decode(String.self, forKey: .deviceID)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "胡桃桌面摆件"
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? "available"
        host = ""
    }

    init(deviceID: String, name: String, status: String, host: String) {
        self.deviceID = deviceID
        self.name = name
        self.status = status
        self.host = host
    }
}

enum DeskDeviceDiscovery {
    static func localIPv4Address(preferredPeer: String? = nil) -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }
        var candidates: [String] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var address = interface.ifa_addr.pointee
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(&address, socklen_t(address.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let value = String(decoding: bytes, as: UTF8.self)
            if isPrivateIPv4(value) { candidates.append(value) }
        }
        if let preferredPeer {
            let prefix = preferredPeer.split(separator: ".").prefix(3).joined(separator: ".") + "."
            if let matching = candidates.first(where: { $0.hasPrefix(prefix) }) { return matching }
        }
        return candidates.first
    }

    static func isPrivateIPv4(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 10
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
    }

    static func localSubnetPrefix() -> String? {
        guard let address = localIPv4Address() else { return nil }
        let octets = address.split(separator: ".")
        guard octets.count == 4 else { return nil }
        return octets.dropLast().joined(separator: ".")
    }

    static func scan(subnet: String? = nil) async -> [DirectDeskDevice] {
        let subnet = subnet ?? localSubnetPrefix() ?? "192.168.100"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.55
        configuration.timeoutIntervalForResource = 1
        let session = URLSession(configuration: configuration)
        /* ESP-IDF's HTTP server intentionally accepts only a few sockets.
         * Firing 253 requests at once made the real desk reject the very
         * request that would identify it. Keep a small, bounded fan-out. */
        var devices: [DirectDeskDevice] = []
        for firstHost in stride(from: 2, through: 254, by: 6) {
            let lastHost = min(firstHost + 5, 254)
            let batch = await withTaskGroup(of: DirectDeskDevice?.self, returning: [DirectDeskDevice].self) { group in
                for host in firstHost...lastHost {
                    group.addTask {
                    let address = "\(subnet).\(host)"
                    guard let url = URL(string: "http://\(address):47872/v1/device-info"),
                          let (data, response) = try? await session.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200,
                          var device = try? JSONDecoder().decode(DirectDeskDevice.self, from: data) else { return nil }
                    device.host = address
                    return device
                }
                }
                var results: [DirectDeskDevice] = []
                for await device in group { if let device { results.append(device) } }
                return results
            }
            devices.append(contentsOf: batch)
        }
        return devices.sorted { $0.host < $1.host }
    }

    static func probe(host: String) async -> DirectDeskDevice? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1
        let session = URLSession(configuration: configuration)
        guard let url = URL(string: "http://\(host):47872/v1/device-info"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              var device = try? JSONDecoder().decode(DirectDeskDevice.self, from: data) else { return nil }
        device.host = host
        return device
    }
}
