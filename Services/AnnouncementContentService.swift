import Foundation

struct AnnouncementContentService {
    var session: URLSession = Self.publicSession

    private static let publicSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    func fetchHTML(for item: AnnouncementItem) async throws -> String {
        guard let id = item.officialContentID else {
            throw AnnouncementContentError.unavailable
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "hk4e-ann-api.mihoyo.com"
        components.path = "/common/hk4e_cn/announcement/api/getAnnContent"
        components.queryItems = [
            URLQueryItem(name: "game", value: "hk4e"),
            URLQueryItem(name: "game_biz", value: "hk4e_cn"),
            URLQueryItem(name: "lang", value: "zh-cn"),
            URLQueryItem(name: "bundle_id", value: "hk4e_cn"),
            URLQueryItem(name: "platform", value: "pc"),
            URLQueryItem(name: "region", value: "cn_gf01"),
            URLQueryItem(name: "level", value: "55"),
            URLQueryItem(name: "uid", value: "100000000")
        ]
        guard let url = components.url else {
            throw AnnouncementContentError.unavailable
        }
        var request = URLRequest(url: url)
        request.setValue("PaimonToolbox/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw AnnouncementContentError.serverError
        }
        let result = try JSONDecoder().decode(ContentResponse.self, from: data)
        guard result.retcode == 0 else {
            throw AnnouncementContentError.serverError
        }
        guard let html = result.data?.list.first(where: { $0.ann_id == id })?.content,
              !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnnouncementContentError.unavailable
        }
        return Self.normalizedHTML(html)
    }

    static func normalizedHTML(_ html: String) -> String {
        // The official feed escapes its custom time tags. Keep the dates and nested formatting.
        html.replacingOccurrences(
            of: #"&(?:amp;)?lt;/?t(?=\s|&(?:amp;)?gt;)(?:(?!&(?:amp;)?gt;)[\s\S])*&(?:amp;)?gt;"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private struct ContentResponse: Decodable {
        var retcode: Int
        var data: ContentList?
    }

    private struct ContentList: Decodable {
        var list: [Article]
    }

    private struct Article: Decodable {
        var ann_id: Int
        var content: String?
    }
}

enum AnnouncementContentError: LocalizedError {
    case unavailable
    case serverError

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "这条公告的正文暂不可用，可能已从官方公告列表中下架。"
        case .serverError:
            "公告加载失败，请稍后重试。"
        }
    }
}
