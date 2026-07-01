import Foundation

struct HoYoHTTPClient: @unchecked Sendable {
    var session: URLSession = .shared
    var decoder: JSONDecoder = JSONDecoder()

    func send<T: Decodable>(_ request: URLRequest, as type: T.Type = T.self) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AccountSessionError.networkFailure()
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = body?.isEmpty == false ? "：\(body!)" : ""
            throw AccountSessionError.networkFailure("HTTP \(http.statusCode)\(suffix)")
        }
        return try decoder.decode(T.self, from: data)
    }
}
