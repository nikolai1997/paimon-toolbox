import XCTest
@testable import PaimonToolbox

final class AnnouncementContentServiceTests: XCTestCase {
    override func tearDown() {
        AnnouncementURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchSelectsMatchingArticleWithoutAccountCredentials() async throws {
        AnnouncementURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "hk4e-ann-api.mihoyo.com")
            XCTAssertEqual(request.url?.lastPathComponent, "getAnnContent")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first(where: { $0.name == "uid" })?.value, "100000000")
            return (200, #"{"retcode":0,"data":{"list":[{"ann_id":2,"content":"wrong article"},{"ann_id":7,"content":"<p>正文</p>"}]}}"#)
        }

        let html = try await service().fetchHTML(for: item(id: "7"))

        XCTAssertEqual(html, "<p>正文</p>")
    }

    func testUnavailableAndEmptyArticlesDoNotShowAnotherAnnouncement() async throws {
        for body in [
            #"{"retcode":0,"data":{"list":[{"ann_id":2,"content":"other article"}]}}"#,
            #"{"retcode":0,"data":{"list":[{"ann_id":7,"content":"  "}]}}"#
        ] {
            AnnouncementURLProtocol.handler = { _ in (200, body) }
            do {
                _ = try await service().fetchHTML(for: item(id: "7"))
                XCTFail("Expected unavailable article")
            } catch let error as AnnouncementContentError {
                guard case .unavailable = error else {
                    return XCTFail("Expected unavailable, got \(error)")
                }
            }
        }
    }

    func testFetchRemovesEscapedTimeTagsAndKeepsCompensationDate() async throws {
        let html = #"<p>停服更新补偿：<span style="color: rgb(204, 146, 85);">&lt;t class="t_gl" contenteditable="false"&gt;2026/09/23 06:00&lt;/t&gt;</span>前冒险等阶达到5级及以上的旅行者。</p>"#
        let body = try JSONSerialization.data(withJSONObject: [
            "retcode": 0,
            "data": ["list": [["ann_id": 7, "content": html]]]
        ])
        AnnouncementURLProtocol.handler = { _ in (200, String(decoding: body, as: UTF8.self)) }

        let result = try await service().fetchHTML(for: item(id: "7"))

        XCTAssertEqual(result, #"<p>停服更新补偿：<span style="color: rgb(204, 146, 85);">2026/09/23 06:00</span>前冒险等阶达到5级及以上的旅行者。</p>"#)
    }

    func testLocalTimeTagsPreserveNestedFormattingAndDateRange() {
        let html = #"<p>&lt;t class="t_lc" contenteditable="false"&gt;<span>2026/10/26 04:00</span>&lt;/t&gt; ~ &lt;t class="t_lc"&gt;2026/11/02 03:59&lt;/t&gt;</p>"#

        XCTAssertEqual(
            AnnouncementContentService.normalizedHTML(html),
            "<p><span>2026/10/26 04:00</span> ~ 2026/11/02 03:59</p>"
        )
    }

    func testTimeTagNormalizationKeepsOtherEscapedMarkupAndImages() {
        let html = #"<p>&amp;lt;t class=&quot;t_gl&quot;&amp;gt;2026/09/26 06:00&amp;lt;/t&amp;gt;</p><p>&lt;table&gt;A &amp; B&lt;/table&gt; &lt;script&gt;example&lt;/script&gt;</p><img src="https://example.com/banner.jpg">"#

        XCTAssertEqual(
            AnnouncementContentService.normalizedHTML(html),
            #"<p>2026/09/26 06:00</p><p>&lt;table&gt;A &amp; B&lt;/table&gt; &lt;script&gt;example&lt;/script&gt;</p><img src="https://example.com/banner.jpg">"#
        )
    }

    func testHTTPAndAPIErrorsAreNotTreatedAsContent() async throws {
        for (status, body) in [
            (503, #"{"retcode":0,"data":{"list":[]}}"#),
            (200, #"{"retcode":-1,"data":null}"#)
        ] {
            AnnouncementURLProtocol.handler = { _ in (status, body) }
            do {
                _ = try await service().fetchHTML(for: item(id: "7"))
                XCTFail("Expected server error")
            } catch let error as AnnouncementContentError {
                guard case .serverError = error else {
                    return XCTFail("Expected server error, got \(error)")
                }
            }
        }
    }

    func testReadAvailabilityDistinguishesOfficialWebAndSynthesizedItems() {
        XCTAssertTrue(item(id: "7").canReadFullContent)
        XCTAssertFalse(item(id: "gacha-7").canReadFullContent)
        XCTAssertFalse(item(id: "miyoushe-7").canReadFullContent)
        XCTAssertFalse(item(id: "-7").canReadFullContent)
        XCTAssertFalse(item(id: "miyoushe-7", url: URL(string: "http://www.miyoushe.com/ys/article/7")).canReadFullContent)
        XCTAssertTrue(item(id: "miyoushe-7", url: URL(string: "https://www.miyoushe.com/ys/article/7")).canReadFullContent)
    }

    private func service() -> AnnouncementContentService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnnouncementURLProtocol.self]
        return AnnouncementContentService(session: URLSession(configuration: configuration))
    }

    private func item(id: String, url: URL? = nil) -> AnnouncementItem {
        AnnouncementItem(
            id: id, title: "测试公告", subtitle: nil, url: url, bannerURL: nil,
            startsAt: nil, endsAt: nil, typeLabel: nil
        )
    }
}

private final class AnnouncementURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler, let url = request.url else {
                throw URLError(.badServerResponse)
            }
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
