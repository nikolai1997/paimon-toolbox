import Foundation

struct MapWebSessionContext: Equatable {
    static let mapURL = URL(string: "https://act.mihoyo.com/ys/app/interactive-map/index.html")!
    static let guest = MapWebSessionContext(accountID: nil, cookies: [])

    let accountID: String?
    let cookies: [AccountWebCookie]

    init(accountID: String?, cookies: [AccountWebCookie]) {
        self.accountID = accountID
        self.cookies = cookies
    }

    init(accountContext: SignInWebVerificationContext) {
        accountID = accountContext.accountID
        let permittedNames: Set<String> = [
            "account_id", "account_id_v2", "cookie_token", "cookie_token_v2",
            "ltuid", "ltuid_v2", "ltmid", "ltmid_v2", "ltoken", "ltoken_v2"
        ]
        cookies = accountContext.cookies.filter { permittedNames.contains($0.name) }
    }
}

enum OfficialMapNavigationPolicy {
    static func allows(_ url: URL, isMainFrame: Bool) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else { return false }

        if isMainFrame {
            return host == "act.mihoyo.com"
                && url.path.hasPrefix("/ys/app/interactive-map/")
        }

        return ["mihoyo.com", "miyoushe.com", "geetest.com", "geevisit.com"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }

    static func cookies(for session: MapWebSessionContext, now: Date = Date()) -> [HTTPCookie] {
        session.cookies.compactMap { cookie in
            HTTPCookie(properties: [
                .domain: ".mihoyo.com", .path: "/", .name: cookie.name,
                .value: cookie.value, .secure: "TRUE",
                .expires: now.addingTimeInterval(24 * 60 * 60)
            ])
        }
    }
}
