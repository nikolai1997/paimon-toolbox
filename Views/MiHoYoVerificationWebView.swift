import SwiftUI
import WebKit

struct MiHoYoVerificationWebView: NSViewRepresentable {
    let payload: SignInResultPayload
    let fallbackURL: URL
    let webContext: SignInWebVerificationContext?
    let onComplete: (SignInVerificationResult) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(webContext: webContext, onComplete: onComplete, onClose: onClose)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let websiteDataStore = WKWebsiteDataStore.nonPersistent()
        configuration.websiteDataStore = websiteDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "geetest")
        for name in Self.miHoYoBridgeHandlerNames {
            configuration.userContentController.add(context.coordinator, name: name)
        }
        configuration.userContentController.addUserScript(Self.jsBridgeScript())

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = HoYoConstants.mobileUserAgent
        context.coordinator.webView = webView
        clearBrowsingData(in: webView.configuration.websiteDataStore) {
            loadContent(in: webView)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onComplete = onComplete
        context.coordinator.onClose = onClose
        context.coordinator.webContext = webContext
        if webView.url == nil {
            loadContent(in: webView)
        }
    }

    private func loadContent(in webView: WKWebView) {
        if webContext != nil {
            loadWebFallback(in: webView)
            return
        }

        guard let gt = payload.gt, let challenge = payload.challenge else {
            loadWebFallback(in: webView)
            return
        }

        webView.loadHTMLString(geetestHTML(gt: gt, challenge: challenge), baseURL: URL(string: "https://static.geetest.com"))
    }

    private func loadWebFallback(in webView: WKWebView) {
        guard let webContext else {
            webView.load(URLRequest(url: fallbackURL))
            return
        }

        setCookies(webContext.cookies, domains: cookieDomains(for: webContext.url), in: webView) {
            webView.load(URLRequest(url: webContext.url))
        }
    }

    private func clearBrowsingData(in dataStore: WKWebsiteDataStore, completion: @escaping @MainActor @Sendable () -> Void) {
        dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast,
            completionHandler: {
                Task { @MainActor in
                    completion()
                }
            }
        )
    }

    private static let miHoYoBridgeHandlerNames = [
        "mihoyo",
        "miHoYo",
        "MiHoYoJSInterface",
        "MiHoYoJSBridge",
        "HYMobile"
    ]

    private static let defaultCookieDomains = [
        ".mihoyo.com",
        ".miyoushe.com",
        ".hoyoverse.com",
        ".hoyo.com"
    ]

    private func cookieDomains(for url: URL) -> [String] {
        var domains = Self.defaultCookieDomains
        if let host = url.host, !domains.contains(host) {
            domains.append(host)
        }
        return domains
    }

    private func setCookies(_ cookies: [AccountWebCookie], domains: [String], in webView: WKWebView, completion: @escaping () -> Void) {
        guard !cookies.isEmpty else {
            completion()
            return
        }

        let group = DispatchGroup()
        for cookie in cookies {
            for domain in domains {
                group.enter()
                if let httpCookie = HTTPCookie(properties: [
                    .domain: domain,
                    .path: "/",
                    .name: cookie.name,
                    .value: cookie.value,
                    .secure: true,
                    .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 30)
                ]) {
                    webView.configuration.websiteDataStore.httpCookieStore.setCookie(httpCookie) {
                        group.leave()
                    }
                } else {
                    group.leave()
                }
            }
        }
        group.notify(queue: .main, execute: completion)
    }

    private func geetestHTML(gt: String, challenge: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body {
              width: 100%;
              height: 100%;
              margin: 0;
              background: #202426;
              color: #f2f4f5;
              font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            }
            body {
              display: flex;
              align-items: center;
              justify-content: center;
            }
            #geetest-div {
              min-width: 320px;
              min-height: 260px;
              display: flex;
              align-items: center;
              justify-content: center;
              text-align: center;
              color: rgba(242, 244, 245, 0.82);
            }
            .hint {
              position: fixed;
              left: 0;
              right: 0;
              bottom: 28px;
              text-align: center;
              color: rgba(242, 244, 245, 0.68);
              font-size: 14px;
            }
          </style>
        </head>
        <body>
          <div id="geetest-div">正在加载安全验证...</div>
          <div class="hint">完成验证后会自动返回并重试签到</div>
          <script src="https://static.geetest.com/static/js/gt.0.5.2.js"></script>
          <script>
            window.addEventListener('error', function () {
              var box = document.getElementById('geetest-div');
              if (box && !box.dataset.ready) {
                box.textContent = '安全验证组件加载失败，请关闭后稍后重试';
              }
            });
            initGeetest({
              protocol: "https://",
              gt: "\(escapeJavaScript(gt))",
              challenge: "\(escapeJavaScript(challenge))",
              new_captcha: true,
              product: "bind",
              api_server: "api.geetest.com"
            }, function (captchaObj) {
              captchaObj.onReady(function () {
                var box = document.getElementById('geetest-div');
                if (box) {
                  box.dataset.ready = 'true';
                  box.textContent = '';
                }
                captchaObj.verify();
              });
              captchaObj.onSuccess(function () {
                var result = captchaObj.getValidate();
                window.webkit.messageHandlers.geetest.postMessage(result);
              });
            });
          </script>
        </body>
        </html>
        """
    }

    private func escapeJavaScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func jsBridgeScript() -> WKUserScript {
        let source = """
        (function() {
          function post(arg) {
            var handlers = window.webkit && window.webkit.messageHandlers;
            if (handlers && handlers.miHoYo) {
              handlers.miHoYo.postMessage(arg);
              return;
            }
            window.webkit.messageHandlers.mihoyo.postMessage(arg);
          }
          function invoke(method, payload, callback) {
            post(JSON.stringify({ method: method, payload: payload || {}, callback: callback || '' }));
          }
          var bridge = {
            postMessage: post,
            invoke: invoke,
            call: invoke,
            closePage: function() { post('{"method":"closePage"}'); }
          };
          window.MiHoYoJSInterface = window.MiHoYoJSInterface || bridge;
          window.MiHoYoJSBridge = window.MiHoYoJSBridge || bridge;
          window.HYMobile = window.HYMobile || bridge;
          window.miHoYo = window.miHoYo || bridge;
          window.mihoyo = window.mihoyo || bridge;
          window.chrome = window.chrome || {};
          window.chrome.webview = window.chrome.webview || { postMessage: post };

          document.addEventListener('DOMContentLoaded', function() {
            var style = document.createElement('style');
            style.textContent = '::-webkit-scrollbar{display:none}';
            document.head.appendChild(style);
          });

          function makeTouchEvent(source, type) {
            if (typeof Touch !== 'function' || typeof TouchEvent !== 'function') {
              return null;
            }
            var touch = new Touch({
              identifier: Date.now(),
              target: source.target,
              clientX: source.clientX,
              clientY: source.clientY,
              screenX: source.screenX,
              screenY: source.screenY,
              pageX: source.pageX,
              pageY: source.pageY
            });
            return new TouchEvent(type, {
              cancelable: true,
              bubbles: true,
              touches: type === 'touchend' ? [] : [touch],
              targetTouches: type === 'touchend' ? [] : [touch],
              changedTouches: [touch]
            });
          }

          function dispatchTouch(source, type) {
            var event = makeTouchEvent(source, type);
            if (event) {
              source.target.dispatchEvent(event);
              source.preventDefault();
            }
          }

          document.addEventListener('mousedown', function(event) {
            dispatchTouch(event, 'touchstart');
            function move(moveEvent) {
              dispatchTouch(moveEvent, 'touchmove');
            }
            function up(upEvent) {
              dispatchTouch(upEvent, 'touchend');
              document.removeEventListener('mousemove', move);
              document.removeEventListener('mouseup', up);
            }
            document.addEventListener('mousemove', move);
            document.addEventListener('mouseup', up);
          });
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var webContext: SignInWebVerificationContext?
        var onComplete: (SignInVerificationResult) -> Void
        var onClose: () -> Void

        init(
            webContext: SignInWebVerificationContext?,
            onComplete: @escaping (SignInVerificationResult) -> Void,
            onClose: @escaping () -> Void
        ) {
            self.webContext = webContext
            self.onComplete = onComplete
            self.onClose = onClose
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "geetest":
                handleGeetestMessage(message)
            default:
                handleMiHoYoMessage(message)
            }
        }

        private func handleGeetestMessage(_ message: WKScriptMessage) {
            if let dictionary = message.body as? [String: Any],
               let challenge = dictionary["geetest_challenge"] as? String,
               let validate = dictionary["geetest_validate"] as? String {
                let seccode = dictionary["geetest_seccode"] as? String
                onComplete(SignInVerificationResult(challenge: challenge, validate: validate, seccode: seccode))
            }
        }

        private func handleMiHoYoMessage(_ message: WKScriptMessage) {
            let raw: String
            if let value = message.body as? String {
                raw = value
            } else if let data = try? JSONSerialization.data(withJSONObject: message.body),
                      let value = String(data: data, encoding: .utf8) {
                raw = value
            } else {
                return
            }

            guard let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = object["method"] as? String else {
                return
            }

            if method == "closePage" {
                onClose()
                return
            }

            guard let callback = object["callback"] as? String, !callback.isEmpty else {
                return
            }

            let result = resultPayload(for: method, payload: object["payload"])
            executeCallback(callback, result: result)
        }

        private func resultPayload(for method: String, payload: Any?) -> [String: Any] {
            let data: [String: Any]
            switch method {
            case "getCookieToken":
                data = [
                    "cookie_token": webContext?.cookieToken ?? "",
                    "cookieToken": webContext?.cookieToken ?? ""
                ]
            case "getCookieInfo":
                data = [
                    "account_id": webContext?.accountID ?? "",
                    "account_id_v2": webContext?.accountID ?? "",
                    "ltuid": webContext?.accountID ?? "",
                    "ltuid_v2": webContext?.accountID ?? "",
                    "ltmid": webContext?.mid ?? "",
                    "ltmid_v2": webContext?.mid ?? "",
                    "cookie_token": webContext?.cookieToken ?? "",
                    "cookie_token_v2": webContext?.cookieToken ?? "",
                    "ltoken": webContext?.ltoken ?? "",
                    "ltoken_v2": webContext?.ltoken ?? "",
                    "login_ticket": ""
                ]
            case "getCookie":
                data = ["cookie": webContext?.cookieHeader ?? ""]
            case "getAllCookie":
                data = [
                    "cookie": webContext?.cookieHeader ?? "",
                    "cookies": webContext?.cookieHeader ?? ""
                ]
            case "getHTTPRequestHeaders":
                data = [
                    "x-rpc-app_id": HoYoConstants.bbsAppID,
                    "x-rpc-client_type": "2",
                    "x-rpc-device_id": HoYoConstants.deviceID,
                    "x-rpc-device_fp": "",
                    "x-rpc-app_version": HoYoConstants.cnAppVersion,
                    "x-rpc-sdk_version": HoYoConstants.bbsSDKVersion
                ]
            case "getUserInfo":
                data = webContext?.userInfo ?? [:]
            case "getAccountInfo":
                data = webContext?.userInfo ?? [:]
            case "getSelectedGameRole":
                data = selectedGameRoleData()
            case "getUserGameRole":
                data = selectedGameRoleData()
            case "getGameRole":
                data = selectedGameRoleData()
            case "getUserGameRoles":
                data = gameRolesData()
            case "getGameRoles":
                data = gameRolesData()
            case "getRoleList":
                data = gameRolesData()
            case "getDS":
                data = ["DS": HoYoRequestSigner.dsHeader(url: webContext?.url ?? HoYoConstants.signInVerificationURL, body: nil, version: .gen1, salt: HoYoSalt.cnLK2, includeLetters: true)]
            case "getDS2":
                let input = dataSignV2Input(from: payload)
                data = ["DS": HoYoRequestSigner.dsHeader(query: input.query, body: input.body, version: .gen2, salt: HoYoSalt.cnX4, includeLetters: false)]
            case "getCurrentLocale":
                data = ["language": HoYoConstants.languageCode, "timeZone": TimeZone.current.identifier]
            case "getStatusBarHeight":
                data = ["statusBarHeight": 0]
            default:
                data = [:]
            }
            return ["retcode": 0, "message": "", "data": data]
        }

        private func selectedGameRoleData() -> [String: Any] {
            guard let role = webContext?.selectedGameRole else {
                return [:]
            }
            return role.reduce(into: [String: Any]()) { result, item in
                result[item.key] = item.value
            }
        }

        private func gameRolesData() -> [String: Any] {
            let role = selectedGameRoleData()
            let roles = role.isEmpty ? [] : [role]
            return [
                "list": roles,
                "roles": roles,
                "game_roles": roles,
                "gameRoles": roles,
                "selected": role
            ]
        }

        private func dataSignV2Input(from payload: Any?) -> (body: String?, query: String) {
            guard let dictionary = payload as? [String: Any] else {
                return (nil, "")
            }

            let body = dictionary["body"] as? String
            if let query = dictionary["query"] as? String {
                return (body, query)
            }
            guard let query = dictionary["query"] as? [String: Any] else {
                return (body, "")
            }

            let serializedQuery = query.keys.sorted().map { key in
                "\(key)=\(stringValue(query[key]))"
            }.joined(separator: "&")
            return (body, serializedQuery)
        }

        private func stringValue(_ value: Any?) -> String {
            switch value {
            case let string as String:
                return string
            case let number as NSNumber:
                return number.stringValue
            case let value?:
                if JSONSerialization.isValidJSONObject([value]),
                   let data = try? JSONSerialization.data(withJSONObject: value),
                   let json = String(data: data, encoding: .utf8) {
                    return json
                }
                return "\(value)"
            case nil:
                return ""
            }
        }

        private func executeCallback(_ callback: String, result: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: result),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }
            let escapedCallback = callback
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            webView?.evaluateJavaScript("mhyWebBridge(\"\(escapedCallback)\", \(json))")
        }
    }
}
