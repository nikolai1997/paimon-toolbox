import Foundation

struct AppUpdateConfiguration: Decodable {
    var githubFeedURL: String
    var githubReleasesURL: String
    var quarkShareURL: String?
    var publicKey: String

    static var bundled: AppUpdateConfiguration? {
        guard let url = Bundle.module.url(forResource: "software-update", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    var hasValidSigningKey: Bool { Data(base64Encoded: publicKey)?.count == 32 }
    var feedURL: URL? { Self.publicHTTPSURL(githubFeedURL) }
    var releasesURL: URL? { Self.publicHTTPSURL(githubReleasesURL) }
    var manualDownloadURL: URL? {
        guard let url = Self.publicHTTPSURL(quarkShareURL),
              url.host?.lowercased() == "pan.quark.cn", url.path.hasPrefix("/s/"),
              url.path.count > 3 else { return nil }
        return url
    }

    static func publicHTTPSURL(_ raw: String?) -> URL? {
        guard let raw, let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.fragment == nil else { return nil }
        return components.url
    }
}

struct AppUpdateFeedResolver {
    var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    func resolve(configuration: AppUpdateConfiguration) async throws -> URL? {
        guard let url = configuration.feedURL else { return nil }
        try Task.checkCancellation()
        do {
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count <= 2_000_000, Self.isAppcast(data) else { return nil }
            return url
        } catch {
            if Task.isCancelled { throw CancellationError() }
            return nil
        }
    }

    static func isAppcast(_ data: Data) -> Bool {
        let delegate = AppcastProbe()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        return parser.parse() && delegate.isRSS && delegate.hasChannel
    }
}

private final class AppcastProbe: NSObject, XMLParserDelegate {
    var isRSS = false
    var hasChannel = false
    private var depth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if depth == 0 { isRSS = elementName == "rss" }
        if depth == 1 && elementName == "channel" { hasChannel = true }
        depth += 1
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        depth -= 1
    }
}
