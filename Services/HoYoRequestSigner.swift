import CryptoKit
import Foundation

enum HoYoCookieKind {
    case stoken
    case cookieToken
}

enum HoYoDSVersion {
    case gen1
    case gen2
}

enum HoYoSalt {
    static let cnLK2 = "sidQFEglajEz7FA0Aj7HQPV88zpf17SO"
    static let cnX4 = "xV8v4Qu54lUKrEYFZkJhB8cuOh9Asafs"
    static let prod = "JwYDpKvLj6MrMqqYU6jTKF17KNO2PXoS"
}

enum HoYoConstants {
    static let cnAppVersion = "2.95.1"
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) miHoYoBBS/2.95.1"
    static let mobileUserAgent = "Mozilla/5.0 (Linux; Android 15) Mobile miHoYoBBS/2.95.1"
    static let hoyoPlayUserAgent = "HYPContainer/1.1.4.133"
    static let hoyoPlayAppID = "ddxf5dufpuyo"
    static let hoyoPlayClientType = "3"
    static let bbsAppID = "bll8iq97cem8"
    static let bbsClientType = "2"
    static let bbsSDKVersion = "2.16.0"
    static let bbsGameBiz = "bbs_cn"
    /// Keep one Mac-local client identity. A new ID on every launch makes a
    /// normal daily-note read look like a new MiHoYo client.
    static let deviceID = persistedDeviceID()
    static let hoyoPlayDeviceID = randomLowercaseAndNumber(count: 53)
    static let lunaActivityID = "e202311201442471"
    static let languageCode = "zh-cn"
    static let signInVerificationURL = URL(string: "https://act.mihoyo.com/bbs/event/signin/hk4e/index.html?act_id=e202311201442471")!

    private static func randomLowercaseAndNumber(count: Int) -> String {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        return String((0..<count).map { _ in alphabet.randomElement()! })
    }

    private static func persistedDeviceID() -> String {
        let key = "hoyo.mac_client_device_id"
        if let existing = UserDefaults.standard.string(forKey: key)?.lowercased() {
            if UUID(uuidString: existing) != nil {
                return existing
            }
            if existing.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil {
                let first = String(existing.prefix(8))
                let second = String(existing.dropFirst(8).prefix(4))
                let third = String(existing.dropFirst(12).prefix(4))
                let fourth = String(existing.dropFirst(16).prefix(4))
                let fifth = String(existing.dropFirst(20))
                let migrated = [first, second, third, fourth, fifth].joined(separator: "-")
                UserDefaults.standard.set(migrated, forKey: key)
                return migrated
            }
        }
        let value = UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}

enum HoYoRequestSigner {
    static func sortedQuery(for url: URL) -> String {
        guard let query = url.query(percentEncoded: false), !query.isEmpty else {
            return ""
        }
        return query.split(separator: "&").map(String.init).sorted().joined(separator: "&")
    }

    static func cookieHeader(for secrets: AccountSecrets, kind: HoYoCookieKind) -> String {
        switch kind {
        case .stoken:
            return "stuid=\(secrets.stuid);stoken=\(secrets.stoken);mid=\(secrets.mid)"
        case .cookieToken:
            guard let cookieToken = secrets.cookieToken, !cookieToken.isEmpty else {
                return ""
            }
            return "account_id=\(secrets.stuid);cookie_token=\(cookieToken)"
        }
    }

    static func dsHeader(url: URL, body: String?, version: HoYoDSVersion, salt: String, includeLetters: Bool) -> String {
        dsHeader(query: sortedQuery(for: url), body: body, version: version, salt: salt, includeLetters: includeLetters)
    }

    static func dsHeader(query: String, body: String?, version: HoYoDSVersion, salt: String, includeLetters: Bool) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let random = includeLetters ? randomLowercaseAndNumber(count: 6) : String(Int.random(in: 100000..<200000))
        var content = "salt=\(salt)&t=\(timestamp)&r=\(random)"
        if version == .gen2 {
            let normalizedBody = body ?? (salt == HoYoSalt.prod ? "{}" : "")
            content += "&b=\(normalizedBody)&q=\(query)"
        }
        let digest = Insecure.MD5.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(timestamp),\(random),\(digest)"
    }

    private static func randomLowercaseAndNumber(count: Int) -> String {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        return String((0..<count).map { _ in alphabet.randomElement()! })
    }
}
