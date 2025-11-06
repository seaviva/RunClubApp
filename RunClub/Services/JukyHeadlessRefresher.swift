//
//  JukyHeadlessRefresher.swift
//  RunClub
//
//  Headless token fetch from Juky by loading web.juky.app in a hidden WKWebView
//  and reading IndexedDB Spotify tokens. Used when tokens are missing/expired or
//  when a 401 occurs.
//

import Foundation
import WebKit

enum JukyHeadlessRefresher {
    static func refreshToken() async -> Bool {
        await withCheckedContinuation { cont in
            let config = WKWebViewConfiguration()
            let controller = WKUserContentController()

            // Shim postMessage bridge
            let shim = "window.ReactNativeWebView = window.ReactNativeWebView || { postMessage: (msg) => window.webkit?.messageHandlers?.runclub?.postMessage?.(msg) };"
            let shimScript = WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            controller.addUserScript(shimScript)

            // Script to read IndexedDB tokens
            let js = """
              const sendMessage = (type, data) => {
                try { window.ReactNativeWebView.postMessage(JSON.stringify({type, data})); } catch (e) {}
              };
              document.documentElement.style.opacity = 0;
              document.documentElement.style.backgroundColor = '#121212';
              document.body.style.opacity = 0;
              window.addEventListener('load', async () => {
                try {
                  const db = await new Promise((resolve, reject) => {
                    const request = indexedDB.open('SpotifyTokensDatabase');
                    request.onsuccess = () => resolve(request.result);
                    request.onerror = () => reject(request.error);
                  });
                  if (db.objectStoreNames.length > 0) {
                    const tx = db.transaction(['spotifyTokens']);
                    const os = tx.objectStore('spotifyTokens');
                    const res = await new Promise((resolve, reject) => {
                      const g = os.getAll();
                      g.onsuccess = () => resolve(g.result);
                      g.onerror = () => reject(g.error);
                    });
                    if (res.length > 0) { sendMessage('AUTH_DATA', res[0]); return; }
                  }
                  sendMessage('NOT_LOGGED_IN', {});
                } catch (e) {
                  sendMessage('FAIL_AUTH', {});
                }
              });
            """
            let jsScript = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            controller.addUserScript(jsScript)

            final class Handler: NSObject, WKScriptMessageHandler {
                let done: (Bool) -> Void
                init(done: @escaping (Bool) -> Void) { self.done = done }
                func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
                    guard message.name == "runclub", let body = message.body as? String, let data = body.data(using: .utf8) else { return }
                    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = obj["type"] as? String else { return }
                    switch type {
                    case "AUTH_DATA":
                        if let dict = obj["data"] as? [String: Any] {
                            let access = (dict["accessToken"] as? String) ?? (dict["access_token"] as? String)
                            let refresh = (dict["refreshToken"] as? String) ?? (dict["refresh_token"] as? String)
                            var expiresAt: Date? = nil
                            if let ttl = dict["expiresIn"] as? Double { expiresAt = Date().addingTimeInterval(ttl) }
                            if let exp = dict["expiresAt"] as? Double { expiresAt = Date(timeIntervalSince1970: exp) }
                            if let token = access {
                                AuthService.setOverrideTokens(accessToken: token, refreshToken: refresh, expiresAt: expiresAt)
                                done(true)
                                return
                            }
                        }
                        done(false)
                    case "NOT_LOGGED_IN", "FAIL_AUTH":
                        done(false)
                    default:
                        break
                    }
                }
            }

            let handler = Handler(done: { ok in cont.resume(returning: ok) })
            controller.add(handler, name: "runclub")
            config.userContentController = controller

            Task { @MainActor in
                let webView = WKWebView(frame: .zero, configuration: config)
                webView.isHidden = true
                webView.customUserAgent = Config.jukyWebViewUserAgent
                webView.load(URLRequest(url: URL(string: Config.jukyWebURL)!))
            }
        }
    }
}


