import Foundation

struct HoYoDeviceFingerprintClient: Sendable {
    private let httpClient: HoYoHTTPClient

    init(httpClient: HoYoHTTPClient = HoYoHTTPClient()) {
        self.httpClient = httpClient
    }

    func fetch(existingFingerprint: String?) async throws -> String {
        let url = URL(string: "https://public-data-api.mihoyo.com/device-fp/api/getFp")!
        let body = DeviceFingerprintRequest(
            deviceID: Self.randomHex(count: 16),
            bbsDeviceID: HoYoConstants.deviceID,
            seedID: UUID().uuidString.lowercased(),
            seedTime: String(Int64(Date().timeIntervalSince1970 * 1_000)),
            platform: "2",
            deviceFingerprint: Self.validSeed(existingFingerprint),
            appName: "bbs_cn",
            extFields: try Self.extFieldsJSON()
        )
        let encoded = try JSONEncoder().encode(body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = encoded
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(HoYoConstants.userAgent, forHTTPHeaderField: "User-Agent")

        let response: HoYoResponse<DeviceFingerprintResponse> = try await httpClient.send(request)
        guard response.retcode == 0,
              let value = response.data?.deviceFingerprint.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            let message = response.message.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AccountSessionError.apiFailureResponse(
                retcode: response.retcode,
                message: message.isEmpty ? "设备指纹申请失败" : message
            )
        }
        return value
    }

    private static func validSeed(_ value: String?) -> String {
        guard let value, value.range(of: "^[0-9a-fA-F]{13}$", options: .regularExpression) != nil else {
            return randomHex(count: 13)
        }
        return value.lowercased()
    }

    private static func extFieldsJSON() throws -> String {
        let deviceName = randomUppercaseAndNumber(count: 12)
        let productName = randomUppercaseAndNumber(count: 6)
        let fields: [String: Any] = [
            "proxyStatus": 0,
            "isRoot": 0,
            "romCapacity": "512",
            "deviceName": deviceName,
            "productName": productName,
            "romRemain": "512",
            "hostname": "android-device",
            "screenSize": "1440x2905",
            "isTablet": 0,
            "aaid": "",
            "model": deviceName,
            "brand": "XiaoMi",
            "hardware": "qcom",
            "deviceType": "OP5913L1",
            "devId": "REL",
            "serialNumber": "unknown",
            "sdCapacity": 512_215,
            "buildTime": "1693626947000",
            "buildUser": "android-build",
            "simState": 5,
            "ramRemain": "239814",
            "appUpdateTimeDiff": 1_702_604_034_482,
            "deviceInfo": "XiaoMi\\/\(productName)\\/OP5913L1:13\\/SKQ1.221119.001\\/release:user\\/release-keys",
            "vaid": "",
            "buildType": "user",
            "sdkVersion": "34",
            "ui_mode": "UI_MODE_TYPE_NORMAL",
            "isMockLocation": 0,
            "cpuType": "arm64-v8a",
            "isAirMode": 0,
            "ringMode": 2,
            "chargeStatus": 1,
            "manufacturer": "XiaoMi",
            "emulatorStatus": 0,
            "appMemory": "512",
            "osVersion": "14",
            "vendor": "unknown",
            "accelerometer": "1.4883357x7.1712894x6.2847486",
            "sdRemain": 239_600,
            "buildTags": "release-keys",
            "packageName": "com.mihoyo.hyperion",
            "networkType": "WiFi",
            "oaid": "",
            "debugStatus": 1,
            "ramCapacity": "469679",
            "magnetometer": "20.081251x-27.487501x2.1937501",
            "display": "\(productName)_13.1.0.181(CN01)",
            "appInstallTimeDiff": 1_688_455_751_496,
            "packageVersion": "2.20.1",
            "gyroscope": "0.030226856x0.014647375x0.010652636",
            "batteryStatus": 100,
            "hasKeyboard": 0,
            "board": "taro",
        ]
        let data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func randomHex(count: Int) -> String {
        randomString(alphabet: Array("0123456789abcdef"), count: count)
    }

    private static func randomUppercaseAndNumber(count: Int) -> String {
        randomString(alphabet: Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"), count: count)
    }

    private static func randomString(alphabet: [Character], count: Int) -> String {
        String((0..<count).compactMap { _ in alphabet.randomElement() })
    }
}

private struct DeviceFingerprintRequest: Encodable {
    var deviceID: String
    var bbsDeviceID: String
    var seedID: String
    var seedTime: String
    var platform: String
    var deviceFingerprint: String
    var appName: String
    var extFields: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case bbsDeviceID = "bbs_device_id"
        case seedID = "seed_id"
        case seedTime = "seed_time"
        case platform
        case deviceFingerprint = "device_fp"
        case appName = "app_name"
        case extFields = "ext_fields"
    }
}

private struct DeviceFingerprintResponse: Decodable {
    var deviceFingerprint: String

    enum CodingKeys: String, CodingKey {
        case deviceFingerprint = "device_fp"
    }
}
