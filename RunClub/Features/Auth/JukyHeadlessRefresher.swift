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
            final class ResumeBox {
                private var resumed = false
                func tryResume() -> Bool {
                    if resumed { return false }
                    resumed = true
                    return true
                }
            }
            let box = ResumeBox()
            Task { @MainActor in
                let config = WKWebViewConfiguration()
                let controller = WKUserContentController()
                print("[JUKY] JukyHeadlessRefresher.refreshToken() begin")

                // Shim postMessage bridge
                let shim = "window.ReactNativeWebView = window.ReactNativeWebView || { postMessage: (msg) => window.webkit?.messageHandlers?.runclub?.postMessage?.(msg) };"
                let shimScript = WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: false)
                controller.addUserScript(shimScript)

                // Script to read IndexedDB tokens
                let webviewURL = Config.jukyWebURL
                let js = """
                  const WEBVIEW_URL = "\(webviewURL)";

                  const sendMessage = (type, data) => {
                    try { window.ReactNativeWebView.postMessage(JSON.stringify({type, data})); } catch (e) {}
                  };

                  document.documentElement.style.opacity = 0;
                  document.documentElement.style.backgroundColor = '#121212';
                  document.body.style.opacity = 0;

                  // let retriesAttempts = parseInt(
                  //   sessionStorage.getItem("retriesAttempts") ?? "2",
                  //   10
                  // );

                  window.addEventListener('load', async () => { 
                    const pageURL = new URL(window.location.href);
                    // sendMessage("DEBUG_INFO", pageURL.href);          

                    if (pageURL.host === "web.juky.app") {
                      // Wait for the login callback to be processed
                      if (pageURL.href.includes("/login")) {
                        // In case page didn't redirect
                        window.setTimeout(() => {
                          window.location.href = WEBVIEW_URL;
                        }, 1000);
                        return;
                      }

                      try {
                        const db = await new Promise((resolve, reject) => {
                          const request = window.indexedDB.open("SpotifyTokensDatabase");
                          request.onsuccess = () => resolve(request.result);
                          request.onerror = () => reject(request.error);
                        });

                        if (db.objectStoreNames.length > 0) {
                          const transaction = db.transaction(["spotifyTokens"]);
                          const objectStore = transaction.objectStore("spotifyTokens");
                          const res = await new Promise((resolve, reject) => {
                            const storeResult = objectStore.getAll();
                            storeResult.onsuccess = () => resolve(storeResult.result);
                            storeResult.onerror = () => reject(storeResult.error);
                          });

                          if (res.length > 0) {
                            // Sort tokens by expiry date (the most lasting one should be first)
                            // res.sort((a, b) => (a.expiry > b.expiry ? -1 : 1));
                            res.sort((a, b) => (a.expiry > b.expiry ? 1 : -1));
                            sendMessage("AUTH_DATA", res[0]);
                            return;
                          }
                        }
                      } catch (e) {}

                      // Failed loading - retry couple times
                      // if (retriesAttempts > 0) {
                      //   retriesAttempts--;
                      //   sessionStorage.setItem("retriesAttempts", String(retriesAttempts));
                      //   window.setTimeout(() => {
                      //     window.location.href = WEBVIEW_URL;
                      //   }, 1000);
                      //   return;
                      // }

                      // Go to spotify authorization page
                      document.querySelector("button")?.click();
                    } else {
                      // Check if user is already authorized in spotify page before, just click "authorize" automatically
                      // (Lost/expired token case)
                      const authAcceptElement = document.querySelector(
                        '[data-testid="auth-accept"]'
                      );
                      if (authAcceptElement) {
                        authAcceptElement.click();
                        return;
                      }

                      sendMessage('NOT_LOGGED_IN', {});
                    }
                  });
                """
                let jsScript = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
                controller.addUserScript(jsScript)

                final class Handler: NSObject, WKScriptMessageHandler {
                    let done: (Bool) -> Void
                    private var handled = false
                    init(done: @escaping (Bool) -> Void) { self.done = done }
                    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
                        guard !handled else { return }
                        guard message.name == "runclub", let body = message.body as? String, let data = body.data(using: .utf8) else { return }
                        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = obj["type"] as? String else { return }
                        switch type {
                        case "AUTH_DATA":
                            print("[JUKY] JukyHeadlessRefresher.refreshToken() AUTH_DATA")
                            if let dict = obj["data"] as? [String: Any] {
                                let access = (dict["accessToken"] as? String) ?? (dict["access_token"] as? String)
                                let refresh = (dict["refreshToken"] as? String) ?? (dict["refresh_token"] as? String)
                                var expiresAt: Date? = nil
                                if let ttl = dict["expiresIn"] as? Double { expiresAt = Date().addingTimeInterval(ttl) }
                                if let exp = dict["expiresAt"] as? Double { expiresAt = Date(timeIntervalSince1970: exp) }
                                if let token = access {
                                    handled = true
                                    AuthService.setOverrideTokens(accessToken: token, refreshToken: refresh, expiresAt: expiresAt)
                                    done(true)
                                    return
                                }
                            }
                            handled = true
                            done(false)
                        case "NOT_LOGGED_IN", "FAIL_AUTH":
                            print("[JUKY] JukyHeadlessRefresher.refreshToken() \(type)")
                            handled = true
                            done(false)
                        case "DEBUG_INFO":
                            print("[JUKY] JukyHeadlessRefresher.refreshToken() DEBUG_INFO \(obj["data"] ?? "nil")")
                        default:
                            break
                        }
                    }
                }

                config.userContentController = controller

                let webView = WKWebView(frame: .zero, configuration: config)
                webView.isHidden = true
                webView.customUserAgent = Config.jukyWebViewUserAgent
                
                // WKWebView needs to be in a view hierarchy to load pages
                if let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow }) {
                    window.addSubview(webView)
                }
                
                let handler = Handler(done: { ok in
                    webView.removeFromSuperview()
                    if box.tryResume() { cont.resume(returning: ok) }
                })
                controller.add(handler, name: "runclub")
                
                webView.load(URLRequest(url: URL(string: Config.jukyWebURL)!))

                // Safety timeout so callers don't hang indefinitely if nothing comes back
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    webView.removeFromSuperview()
                    if box.tryResume() { cont.resume(returning: false) }
                }
            }
        }
    }
}


