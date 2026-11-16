import XCTest
import Sparkle
@testable import PaimonToolbox

final class AppUpdateTests: XCTestCase {
    @MainActor
    func testBackgroundCurrentVersionNeverShowsFallbackPrompt() {
        let controller = AppUpdateController(configuration: configuration())
        let native = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        controller.showsManualDownloadPrompt = true

        controller.updater(native.updater, didFinishUpdateCycleFor: .updatesInBackground,
                           error: NSError(domain: SUSparkleErrorDomain, code: 1001))

        XCTAssertFalse(controller.showsManualDownloadPrompt)
        XCTAssertEqual(controller.status, "已是最新版本")
    }

    @MainActor
    func testBackgroundFeedFailuresStaySilentAndDoNotClaimCurrentVersion() {
        let controller = AppUpdateController(configuration: configuration())
        let native = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let errors = [NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut),
                      NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet),
                      NSError(domain: SUSparkleErrorDomain, code: 1002),
                      NSError(domain: SUSparkleErrorDomain, code: 2001)]
        for check in [SPUUpdateCheck.updatesInBackground, .updateInformation] {
            for error in errors {
                controller.updater(native.updater, didFinishUpdateCycleFor: check, error: error)
                XCTAssertFalse(controller.showsManualDownloadPrompt)
                XCTAssertEqual(controller.status, "自动检查未完成，将在下次检查时重试")
            }
        }
    }

    @MainActor
    func testManualFailureStillOffersQuarkDownload() {
        let controller = AppUpdateController(configuration: configuration())
        let native = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater(native.updater, didFinishUpdateCycleFor: .updates,
                           error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        XCTAssertTrue(controller.showsManualDownloadPrompt)
    }

    @MainActor
    func testDownloadFailurePromptsOnlyAfterNewVersionWasFoundAndResetsNextCycle() throws {
        let controller = AppUpdateController(configuration: configuration())
        let native = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let item = try XCTUnwrap(SUAppcastItem(dictionary: [
            "sparkle:version": "999.0.0",
            "enclosure": ["url": "https://example.com/update.dmg", "length": "100"]
        ]))
        controller.updater(native.updater, didFindValidUpdate: item)
        controller.updater(native.updater, didFinishUpdateCycleFor: .updatesInBackground,
                           error: NSError(domain: SUSparkleErrorDomain, code: 2001))
        XCTAssertTrue(controller.showsManualDownloadPrompt)

        controller.updater(native.updater, didFinishUpdateCycleFor: .updatesInBackground,
                           error: NSError(domain: SUSparkleErrorDomain, code: 1002))
        XCTAssertFalse(controller.showsManualDownloadPrompt)
    }

    @MainActor
    func testSuccessfulCycleClearsOldPrompt() {
        let controller = AppUpdateController(configuration: configuration())
        let native = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        controller.showsManualDownloadPrompt = true
        controller.updater(native.updater, didFinishUpdateCycleFor: .updatesInBackground, error: nil)
        XCTAssertFalse(controller.showsManualDownloadPrompt)
    }

    @MainActor
    func testSignatureFailureAndCancellationNeverShowFallbackPrompt() {
        let controller = AppUpdateController(configuration: configuration())
        let native = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let errors = [NSError(domain: SUSparkleErrorDomain, code: 3001),
                      NSError(domain: SUSparkleErrorDomain, code: 3002),
                      NSError(domain: SUSparkleErrorDomain, code: 4007),
                      NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)]
        for check in [SPUUpdateCheck.updates, .updatesInBackground] {
            for error in errors {
                controller.showsManualDownloadPrompt = true
                controller.updater(native.updater, didFinishUpdateCycleFor: check, error: error)
                XCTAssertFalse(controller.showsManualDownloadPrompt)
            }
        }
    }

    @MainActor
    func testAutomaticUpdateSwitchPersistsBothPreferencesAcrossControllerRecreation() throws {
        guard Bundle.main.bundleIdentifier != "com.nikolai.paimon-toolbox" else {
            throw XCTSkip("Must not change the installed app's update preferences")
        }
        let keys = ["SUEnableAutomaticChecks", "SUAutomaticallyUpdate"]
        let defaults = UserDefaults.standard
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }

        let updater = AppUpdateController()
        updater.setAutomaticUpdates(false)
        XCTAssertFalse(updater.automaticallyChecks)
        XCTAssertFalse(updater.automaticallyDownloads)
        XCTAssertFalse(AppUpdateController().automaticallyUpdates)

        updater.setAutomaticUpdates(true)
        let restored = AppUpdateController()
        XCTAssertTrue(restored.automaticallyChecks)
        XCTAssertTrue(restored.automaticallyDownloads)
        XCTAssertTrue(restored.automaticallyUpdates)

        defaults.set(true, forKey: "SUEnableAutomaticChecks")
        defaults.set(false, forKey: "SUAutomaticallyUpdate")
        let migrated = AppUpdateController()
        XCTAssertFalse(migrated.automaticallyChecks)
        XCTAssertFalse(migrated.automaticallyDownloads)
        XCTAssertFalse(migrated.automaticallyUpdates)
    }

    func testBundledConfigurationHasSigningKeyAndGitHubFeed() throws {
        let config = try XCTUnwrap(AppUpdateConfiguration.bundled)
        XCTAssertTrue(config.hasValidSigningKey)
        XCTAssertEqual(config.feedURL?.lastPathComponent, "appcast.xml")
    }

    override func tearDown() {
        UpdateFeedURLProtocol.handler = nil
        super.tearDown()
    }

    func testAutomaticFeedIsGitHubAndQuarkIsOnlyAManualLink() {
        let config = configuration()
        XCTAssertEqual(config.feedURL?.host, "github.example.com")
        XCTAssertEqual(config.manualDownloadURL?.host, "pan.quark.cn")
    }

    func testPublicSharingPageIsNotAssumedToBeAnUpdateFeed() {
        var config = configuration()
        config.quarkShareURL = nil
        XCTAssertNotNil(config.feedURL)
        XCTAssertNil(config.manualDownloadURL)
        for url in ["https://www.jianguoyun.com/p/example", "https://pan.quark.cn.evil.example/s/example", "https://pan.quark.cn/s/"] {
            config.quarkShareURL = url
            XCTAssertNil(config.manualDownloadURL)
        }
    }

    func testCredentialsAndNonHTTPSURLsAreRejected() {
        for value in ["http://example.com/appcast.xml", "https://account:password@example.com/appcast.xml", "file:///tmp/appcast.xml", "https:///appcast.xml"] {
            XCTAssertNil(AppUpdateConfiguration.publicHTTPSURL(value), value)
        }
        XCTAssertNotNil(AppUpdateConfiguration.publicHTTPSURL("https://example.com/appcast.xml"))
    }

    func testUnsignedPageAndMalformedXMLCannotBecomeAnAppcast() {
        XCTAssertFalse(AppUpdateFeedResolver.isAppcast(Data("<html><body>请登录</body></html>".utf8)))
        XCTAssertFalse(AppUpdateFeedResolver.isAppcast(Data("<rss><channel>".utf8)))
        XCTAssertTrue(AppUpdateFeedResolver.isAppcast(Data("<rss version=\"2.0\"><channel/></rss>".utf8)))
    }

    func testDownloadFailureAllowsFallbackButSignatureFailureAndCancellationDoNot() {
        XCTAssertTrue(AppUpdateController.isConnectionFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)))
        XCTAssertTrue(AppUpdateController.isConnectionFailure(NSError(domain: "SUSparkleErrorDomain", code: 2001)))
        XCTAssertFalse(AppUpdateController.isConnectionFailure(NSError(domain: "SUSparkleErrorDomain", code: 3001)))
        XCTAssertFalse(AppUpdateController.isConnectionFailure(NSError(domain: "SUSparkleErrorDomain", code: 3002)))
        XCTAssertFalse(AppUpdateController.isConnectionFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        XCTAssertFalse(AppUpdateController.isConnectionFailure(NSError(
            domain: "SUSparkleErrorDomain", code: 2001,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)]
        )))
    }

    func testAutomaticCheckUsesGitHubWithoutSendingCookies() async throws {
        let config = configuration()
        UpdateFeedURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "github.example.com")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return (200, "<rss version=\"2.0\"><channel/></rss>")
        }
        let selected = try await resolver().resolve(configuration: config)
        XCTAssertEqual(selected, config.feedURL)
    }

    func testHTMLSharePageIsSkippedAndNeverSelectedAsAnAutomaticFeed() async throws {
        UpdateFeedURLProtocol.handler = { _ in (200, "<html><body>Download</body></html>") }
        let selected = try await resolver().resolve(configuration: configuration())
        XCTAssertNil(selected)
    }

    func testConnectionFailureDoesNotTreatQuarkShareAsAnAutomaticFeed() async throws {
        UpdateFeedURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "github.example.com")
            throw URLError(.notConnectedToInternet)
        }
        let selected = try await resolver().resolve(configuration: configuration())
        XCTAssertNil(selected)
    }

    private func configuration() -> AppUpdateConfiguration {
        AppUpdateConfiguration(
            githubFeedURL: "https://github.example.com/appcast.xml",
            githubReleasesURL: "https://github.example.com/releases",
            quarkShareURL: "https://pan.quark.cn/s/example",
            publicKey: Data(repeating: 1, count: 32).base64EncodedString()
        )
    }

    private func resolver() -> AppUpdateFeedResolver {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateFeedURLProtocol.self]
        return AppUpdateFeedResolver(session: URLSession(configuration: config))
    }
}

private final class UpdateFeedURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler, let url = request.url else { throw URLError(.badServerResponse) }
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
