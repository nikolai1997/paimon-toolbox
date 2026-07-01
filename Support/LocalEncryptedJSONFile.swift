import CryptoKit
import Foundation
import Security

struct LocalEncryptedJSONFile {
    private let fileURL: URL
    private let keyURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL, keyURL: URL? = nil) {
        self.fileURL = fileURL
        self.keyURL = keyURL ?? fileURL.deletingLastPathComponent().appending(path: "account-encryption.key")
    }

    func load<T: Codable>(_ type: T.Type) throws -> T? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        if let encrypted = try? decoder.decode(EncryptedLocalJSONEnvelope.self, from: data) {
            return try decrypt(encrypted, as: type)
        }

        let legacyValue = try decoder.decode(type, from: data)
        try save(legacyValue)
        return legacyValue
    }

    func save<T: Encodable>(_ value: T) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let envelope = try encrypt(value)
        try encoder.encode(envelope).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func encrypt<T: Encodable>(_ value: T) throws -> EncryptedLocalJSONEnvelope {
        let key = try loadOrCreateKey()
        let plaintext = try encoder.encode(value)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw AccountSessionError.invalidResponse("无法加密本地账号数据")
        }
        return EncryptedLocalJSONEnvelope(
            version: 1,
            algorithm: EncryptedLocalJSONEnvelope.supportedAlgorithm,
            combined: combined.base64EncodedString()
        )
    }

    private func decrypt<T: Decodable>(_ envelope: EncryptedLocalJSONEnvelope, as type: T.Type) throws -> T {
        guard envelope.version == 1, envelope.algorithm == EncryptedLocalJSONEnvelope.supportedAlgorithm else {
            throw AccountSessionError.invalidResponse("不支持的本地账号数据加密格式")
        }
        guard let combined = Data(base64Encoded: envelope.combined) else {
            throw AccountSessionError.invalidResponse("本地账号数据密文格式无效")
        }

        let key = try loadOrCreateKey()
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        return try decoder.decode(type, from: plaintext)
    }

    private func loadOrCreateKey() throws -> SymmetricKey {
        try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: keyURL.path) {
            let data = try Data(contentsOf: keyURL)
            guard data.count == 32 else {
                throw AccountSessionError.invalidResponse("本地账号数据密钥格式无效")
            }
            return SymmetricKey(data: data)
        }

        let byteCount = 32
        var keyData = Data(count: byteCount)
        let status = keyData.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, byteCount, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw AccountSessionError.localStorageUnavailable("无法生成本地账号数据密钥（\(status)）")
        }

        try keyData.write(to: keyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        return SymmetricKey(data: keyData)
    }
}

private struct EncryptedLocalJSONEnvelope: Codable {
    static let supportedAlgorithm = "AES.GCM.256"

    var version: Int
    var algorithm: String
    var combined: String
}
