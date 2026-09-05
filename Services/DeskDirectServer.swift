import CryptoKit
import Foundation
import Network

struct DeskHTTPRequest: Equatable {
    var method: String
    var target: String
    var headers: [String: String]
    var body: Data
}

enum DeskHTTPRequestParseError: Error, Equatable {
    case incomplete
    case invalid
    case tooLarge
}

enum DeskHTTPRequestParser {
    static let maximumRequestSize = 64 * 1024
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    static func parse(_ data: Data) throws -> DeskHTTPRequest {
        guard data.count <= maximumRequestSize else { throw DeskHTTPRequestParseError.tooLarge }
        guard let headerRange = data.range(of: headerTerminator) else {
            throw DeskHTTPRequestParseError.incomplete
        }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw DeskHTTPRequestParseError.invalid
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw DeskHTTPRequestParseError.invalid }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count == 3, requestParts[2].hasPrefix("HTTP/1.") else {
            throw DeskHTTPRequestParseError.invalid
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else {
                throw DeskHTTPRequestParseError.invalid
            }
            let name = line[..<separator].lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, headers[name] == nil else {
                throw DeskHTTPRequestParseError.invalid
            }
            headers[name] = value
        }
        guard headers["transfer-encoding"] == nil else {
            throw DeskHTTPRequestParseError.invalid
        }
        let contentLength: Int
        if let rawLength = headers["content-length"] {
            guard let parsedLength = Int(rawLength), parsedLength >= 0 else {
                throw DeskHTTPRequestParseError.invalid
            }
            contentLength = parsedLength
        } else {
            contentLength = 0
        }
        let bodyStart = headerRange.upperBound
        let expectedLength = bodyStart + contentLength
        guard expectedLength <= maximumRequestSize else { throw DeskHTTPRequestParseError.tooLarge }
        guard data.count >= expectedLength else { throw DeskHTTPRequestParseError.incomplete }
        guard data.count == expectedLength else { throw DeskHTTPRequestParseError.invalid }
        return DeskHTTPRequest(
            method: requestParts[0],
            target: requestParts[1],
            headers: headers,
            body: Data(data[bodyStart..<expectedLength])
        )
    }
}

/// A small LAN-only HTTP/UDP service owned by the Mac toolbox.
///
/// It deliberately exposes only the already-normalized desk snapshot and two
/// commands.  MiHoYo cookies, HA tokens and verification proofs never cross
/// this service.  The device receives a random bearer token only after the
/// user approves the eight-character code shown on the desk.
@MainActor
final class DeskDirectServer {
    nonisolated static let httpPort: UInt16 = 47871
    nonisolated static let discoveryPort: UInt16 = 45871
    nonisolated static let tokenLifetime: TimeInterval = 30 * 24 * 60 * 60
    nonisolated static let pairingLifetime: TimeInterval = 5 * 60

    var onPairingRequest: ((DeskDirectPairingRequest) -> Void)?
    var snapshotProvider: (() async -> Data?)?
    var actionHandler: ((String, Int) async -> Void)?
    var accountIDProvider: (() -> String?)?
    var onDevicePresenceChanged: ((DirectDeskDevice) -> Void)?

    private(set) var isRunning = false
    private(set) var lastError: String?
    private let fingerprint: String
    private var httpListener: NWListener?
    private var discoveryListener: NWListener?
    private var pending: [String: PendingPairing] = [:]
    private var devices: [String: DeskDirectDeviceRecord] = [:]
    private let persistenceURL: URL?
    private let now: () -> Date
    private let queue = DispatchQueue(label: "com.nikolai.paimon-toolbox.desk-direct")

    private struct PendingPairing {
        var request: DeskDirectPairingRequest
        var approvedToken: String?
        var accountID: String?
        var remoteHost: String?
    }

    init(
        persistenceURL: URL? = try? AppPaths.deskDirectDevicesURL,
        now: @escaping () -> Date = { Date() }
    ) {
        let random = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        fingerprint = SHA256.hash(data: random).map { String(format: "%02x", $0) }.joined().prefix(16).description
        self.persistenceURL = persistenceURL
        self.now = now
        if let persistenceURL,
           let records = try? LocalEncryptedJSONFile(fileURL: persistenceURL).load([String: DeskDirectDeviceRecord].self) {
            devices = records
        }
    }

    func start() {
        guard !isRunning else { return }
        do {
            // The desk is an IPv4-only ESP32 client. A default NWListener may
            // publish an IPv6 wildcard socket that looks healthy in the UI but
            // rejects every IPv4 connection from the desk.
            let httpParameters = NWParameters.tcp
            httpParameters.allowLocalEndpointReuse = true
            httpParameters.requiredLocalEndpoint = .hostPort(
                host: .ipv4(IPv4Address("0.0.0.0")!),
                port: NWEndpoint.Port(rawValue: Self.httpPort)!
            )
            let http = try NWListener(using: httpParameters)
            http.newConnectionHandler = { [weak self] connection in
                connection.start(queue: self?.queue ?? .main)
                (self?.queue ?? .main).asyncAfter(deadline: .now() + 10) { [weak connection] in
                    connection?.cancel()
                }
                Task { @MainActor in self?.receiveHTTP(on: connection) }
            }
            http.stateUpdateHandler = { [weak self] state in
                guard case let .failed(error) = state else { return }
                Task { @MainActor in self?.lastError = error.localizedDescription; self?.isRunning = false }
            }
            http.start(queue: queue)
            httpListener = http

            // ESP32 discovery uses an IPv4 subnet broadcast.  A default UDP
            // listener can become IPv6-only on macOS, in which case it looks
            // healthy locally but never receives the desk's broadcast.  Bind
            // this listener explicitly to the IPv4 wildcard address.
            let discoveryParameters = NWParameters.udp
            discoveryParameters.allowLocalEndpointReuse = true
            discoveryParameters.requiredLocalEndpoint = .hostPort(
                host: .ipv4(IPv4Address("0.0.0.0")!),
                port: NWEndpoint.Port(rawValue: Self.discoveryPort)!
            )
            let discovery = try NWListener(using: discoveryParameters)
            discovery.newConnectionHandler = { [weak self] connection in
                connection.start(queue: self?.queue ?? .main)
                Task { @MainActor in self?.receiveDiscovery(on: connection) }
            }
            discovery.stateUpdateHandler = { [weak self] state in
                guard case let .failed(error) = state else { return }
                Task { @MainActor in self?.lastError = error.localizedDescription; self?.isRunning = false }
            }
            discovery.start(queue: queue)
            discoveryListener = discovery
            lastError = nil
            isRunning = true
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    func stop() {
        httpListener?.cancel()
        discoveryListener?.cancel()
        httpListener = nil
        discoveryListener = nil
        pending.removeAll()
        isRunning = false
    }

    func approve(requestID: String, displayCode: String) -> Bool {
        let approvalTime = now()
        prunePending(now: approvalTime)
        guard let current = pending[requestID],
              displayCode.uppercased() == current.request.displayCode.uppercased(),
              let accountID = accountIDProvider?(), !accountID.isEmpty else {
            return false
        }
        let token = Self.randomToken()
        pending[requestID] = PendingPairing(
            request: current.request,
            approvedToken: token,
            accountID: accountID,
            remoteHost: current.remoteHost
        )
        devices[current.request.deviceID] = DeskDirectDeviceRecord(
            deviceID: current.request.deviceID,
            accountID: accountID,
            accessToken: token,
            pairedAt: approvalTime,
            expiresAt: approvalTime.addingTimeInterval(Self.tokenLifetime),
            name: nil,
            host: current.remoteHost,
            lastSeenAt: nil
        )
        persistDevices()
        return true
    }

    func reject(requestID: String) {
        pending.removeValue(forKey: requestID)
    }

    func forget(deviceID: String) {
        devices.removeValue(forKey: deviceID)
        persistDevices()
    }

    func issueAccessToken(for device: DirectDeskDevice, accountID: String) -> String {
        let issuedAt = now()
        let token = Self.randomToken()
        devices[device.deviceID] = DeskDirectDeviceRecord(
            deviceID: device.deviceID,
            accountID: accountID,
            accessToken: token,
            pairedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(Self.tokenLifetime),
            name: device.name,
            host: device.host,
            lastSeenAt: nil
        )
        persistDevices()
        return token
    }

    func knownDevices(now: Date = Date()) -> [DirectDeskDevice] {
        let accountID = accountIDProvider?()
        return devices.values.filter { $0.accountID == accountID && !isExpired($0, now: now) }.map { record in
            let online = record.lastSeenAt.map { now.timeIntervalSince($0) < 75 } ?? false
            return DirectDeskDevice(
                deviceID: record.deviceID,
                name: record.name ?? "胡桃桌面摆件",
                status: online ? "connected" : "saved",
                host: record.host ?? ""
            )
        }.sorted { $0.deviceID < $1.deviceID }
    }

    private func receiveDiscovery(on connection: NWConnection) {
        let fingerprint = fingerprint
        connection.receiveMessage { [weak connection] data, _, _, error in
            guard let connection, let data, error == nil else {
                connection?.cancel()
                return
            }
            let response = Self.discoveryResponse(for: data, fingerprint: fingerprint)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    nonisolated private static func discoveryResponse(for data: Data, fingerprint: String) -> Data {
        let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let nonce = request?["nonce"] as? String ?? ""
        let response: [String: Any] = [
            "protocol": "genshin-desk-discovery-v1",
            "nonce": nonce,
            "bridge_port": Int(Self.httpPort),
            "fingerprint": fingerprint,
            "transport": "mac-direct",
        ]
        return (try? JSONSerialization.data(withJSONObject: response)) ?? Data("{}".utf8)
    }

    private func receiveHTTP(on connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, let connection, error == nil else {
                    connection?.cancel()
                    return
                }
                var accumulated = buffer
                if let data { accumulated.append(data) }
                do {
                    let request = try DeskHTTPRequestParser.parse(accumulated)
                    let response = await self.handleHTTP(request: request, remoteHost: Self.remoteHost(connection.endpoint))
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                } catch DeskHTTPRequestParseError.incomplete where !isComplete {
                    self.receiveHTTP(on: connection, buffer: accumulated)
                } catch DeskHTTPRequestParseError.tooLarge {
                    let response = Self.httpResponse(status: "413 Payload Too Large", body: ["detail": "request too large"])
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                } catch {
                    let response = Self.httpResponse(status: "400 Bad Request", body: ["detail": "invalid HTTP request"])
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
    }

    func handleHTTP(data: Data, remoteHost: String?) async -> Data {
        guard let request = try? DeskHTTPRequestParser.parse(data) else {
            return Self.httpResponse(status: "400 Bad Request", body: ["detail": "invalid HTTP request"])
        }
        return await handleHTTP(request: request, remoteHost: remoteHost)
    }

    private func handleHTTP(request: DeskHTTPRequest, remoteHost: String?) async -> Data {
        guard let url = URL(string: "http://localhost\(request.target)") else {
            return Self.httpResponse(status: "400 Bad Request", body: ["detail": "invalid path"])
        }
        let path = url.path

        if request.method == "POST", path == "/v1/device-pairings/request" {
            return pairingRequest(body: request.body, remoteHost: remoteHost)
        }
        if request.method == "GET", path.hasPrefix("/v1/device-pairings/") {
            let requestID = String(path.dropFirst("/v1/device-pairings/".count))
            return pairingStatus(
                requestID: requestID,
                query: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [],
                remoteHost: remoteHost
            )
        }
        // Keep health unauthenticated so the toolbox and a user can verify
        // that the Mac service is reachable before pairing a device.
        if request.method == "GET", path == "/health" {
            return Self.httpResponse(status: "200 OK", body: ["status": "ok", "mode": "mac-direct"])
        }
        guard let token = Self.bearerToken(request.headers["authorization"]),
              let deviceID = authenticate(token, remoteHost: remoteHost) else {
            return Self.httpResponse(status: "401 Unauthorized", body: ["detail": "device pairing required"])
        }
        markDeviceSeen(deviceID: deviceID)
        if request.method == "GET", path == "/v1/device/state" {
            guard let data = await snapshotProvider?(), let object = try? JSONSerialization.jsonObject(with: data) else {
                return Self.httpResponse(status: "503 Service Unavailable", body: ["detail": "snapshot unavailable"])
            }
            return Self.httpResponse(status: "200 OK", object: object)
        }
        if request.method == "POST", path == "/v1/device/actions" {
            guard let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let action = object["action"] as? String else {
                return Self.httpResponse(status: "400 Bad Request", body: ["detail": "invalid action"])
            }
            let page = object["page"] as? Int ?? 0
            await actionHandler?(action, page)
            return Self.httpResponse(status: "202 Accepted", body: ["accepted": true])
        }
        return Self.httpResponse(status: "404 Not Found", body: ["detail": "not found"])
    }

    private func pairingRequest(body: Data, remoteHost: String?) -> Data {
        let requestTime = now()
        prunePending(now: requestTime)
        guard accountIDProvider?()?.isEmpty == false else {
            return Self.httpResponse(status: "403 Forbidden", body: ["detail": "account sign-in required"])
        }
        guard pending.count < 8,
              pending.values.filter({ $0.remoteHost == remoteHost }).count < 3 else {
            return Self.httpResponse(status: "429 Too Many Requests", body: ["detail": "too many pairing requests"])
        }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let deviceID = object["device_id"] as? String,
              !deviceID.isEmpty else {
            return Self.httpResponse(status: "400 Bad Request", body: ["detail": "device_id is required"])
        }
        let request = DeskDirectPairingRequest(
            requestID: UUID().uuidString.lowercased(),
            deviceID: String(deviceID.prefix(32)),
            displayCode: Self.randomDisplayCode(),
            createdAt: requestTime,
            status: "pending"
        )
        pending[request.requestID] = PendingPairing(
            request: request,
            approvedToken: nil,
            accountID: nil,
            remoteHost: remoteHost
        )
        onPairingRequest?(request)
        return Self.httpResponse(status: "200 OK", body: [
            "request_id": request.requestID,
            "display_code": request.displayCode,
            "fingerprint": fingerprint,
        ])
    }

    private func pairingStatus(requestID: String, query: [URLQueryItem], remoteHost: String?) -> Data {
        prunePending(now: now())
        guard let item = pending[requestID],
              item.remoteHost == remoteHost,
              query.first(where: { $0.name == "display_code" })?.value == item.request.displayCode else {
            return Self.httpResponse(status: "404 Not Found", body: ["detail": "pairing request not found"])
        }
        guard let token = item.approvedToken, let accountID = item.accountID else {
            return Self.httpResponse(status: "200 OK", body: ["status": "pending"])
        }
        pending.removeValue(forKey: requestID)
        return Self.httpResponse(status: "200 OK", body: [
            "status": "approved",
            "transport": "http",
            "access_token": token,
            "account_id": accountID,
        ])
    }

    private func authenticate(_ token: String, remoteHost: String?) -> String? {
        guard let accountID = accountIDProvider?(), !accountID.isEmpty else { return nil }
        let authenticationTime = now()
        return devices.first { _, record in
            record.accessToken == token
                && record.accountID == accountID
                && !isExpired(record, now: authenticationTime)
                && record.host?.isEmpty == false
                && record.host == remoteHost
        }?.key
    }

    private func markDeviceSeen(deviceID: String) {
        guard var record = devices[deviceID] else { return }
        let seenAt = now()
        record.lastSeenAt = seenAt
        record.expiresAt = seenAt.addingTimeInterval(Self.tokenLifetime)
        devices[deviceID] = record
        persistDevices()
        onDevicePresenceChanged?(
            DirectDeskDevice(
                deviceID: deviceID,
                name: record.name ?? "胡桃桌面摆件",
                status: "connected",
                host: record.host ?? ""
            )
        )
    }

    private func prunePending(now: Date) {
        pending = pending.filter { now.timeIntervalSince($0.value.request.createdAt) <= Self.pairingLifetime }
    }

    private func isExpired(_ record: DeskDirectDeviceRecord, now: Date) -> Bool {
        let expiration = record.expiresAt ?? record.pairedAt.addingTimeInterval(Self.tokenLifetime)
        return now >= expiration
    }

    nonisolated private static func remoteHost(_ endpoint: NWEndpoint) -> String? {
        guard case let .hostPort(host, _) = endpoint else { return nil }
        switch host {
        case let .ipv4(address): return address.debugDescription
        case let .ipv6(address): return address.debugDescription
        case let .name(name, _): return name
        @unknown default: return nil
        }
    }

    private func persistDevices() {
        guard let persistenceURL else { return }
        try? LocalEncryptedJSONFile(fileURL: persistenceURL).save(devices)
    }

    private static func randomDisplayCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return (0..<8).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] }.map(String.init).joined()
    }

    private static func randomToken() -> String {
        let data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func bearerToken(_ value: String?) -> String? {
        guard let value, value.hasPrefix("Bearer ") else { return nil }
        return String(value.dropFirst(7))
    }

    private static func httpResponse(status: String, body: [String: Any]) -> Data {
        httpResponse(status: status, object: body)
    }

    private static func httpResponse(status: String, object: Any) -> Data {
        let payload = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(payload.count)\r\n\r\n"
        return Data(header.utf8) + payload
    }
}
