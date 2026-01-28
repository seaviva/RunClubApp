//
//  WebTokenConnectView.swift
//  RunClub
//
//  Created by Assistant on 10/24/25.
//

import SwiftUI
import WebKit

/// WKWebView subclass that hides the keyboard input accessory view (next/prev/Done toolbar)
final class NoInputAccessoryWebView: WKWebView {
    override var inputAccessoryView: UIView? { nil }
}

final class WebTokenMessageHandler: NSObject, WKScriptMessageHandler {
    var onAuth: ((String) -> Void)?
    var onNotLoggedIn: (() -> Void)?
    var onFailAuth: (() -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "runclub" else { return }
        guard let body = message.body as? String else { return }
        print("[WebTokenConnectView] message body=\(body.prefix(300))")
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = obj["type"] as? String {
            switch type {
            case "AUTH_DATA":
                // Support two shapes:
                // 1) data is a stringified JSON with access_token (legacy)
                // 2) data is an object with accessToken/refreshToken/expiresAt|expiresIn (Juky)
                if let dict = obj["data"] as? [String: Any] {
                    let access = (dict["accessToken"] as? String)
                    let refresh = dict["refreshToken"] as? String
                    // expiresAt as epoch seconds or ISO string; or expiresIn seconds
                    var expiresAt: Date? = nil
                    if let exp = dict["expiresAt"] as? Double { expiresAt = Date(timeIntervalSince1970: exp) }
                    else if let expStr = dict["expiresAt"] as? String, let d = Double(expStr) { expiresAt = Date(timeIntervalSince1970: d) }
                    else if let ttl = dict["expiresIn"] as? Double { expiresAt = Date().addingTimeInterval(ttl) }
                    if let token = access {
                        AuthService.setOverrideTokens(accessToken: token, refreshToken: refresh, expiresAt: expiresAt)
                        onAuth?(token)
                    } else { onFailAuth?() }
                } else if let s = obj["data"] as? String, let authData = s.data(using: .utf8) {
                    if let json = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
                       let token = json["access_token"] as? String {
                        AuthService.setOverrideTokens(accessToken: token, refreshToken: nil, expiresAt: nil)
                        onAuth?(token)
                    } else { onFailAuth?() }
                } else { onFailAuth?() }
            case "NOT_LOGGED_IN":
                onNotLoggedIn?()
            case "FAIL_AUTH":
                // keep the sheet open; allow redirect flow to continue
                onFailAuth?()
            // case "DEBUG_INFO":
                // print("[AUTH] WebTokenConnectView.DEBUG_INFO \(obj["data"] ?? "nil")")
            default:
                break
            }
        }
    }
}

struct WebTokenConnectView: View {
    var onAuth: (String) -> Void
    var onFail: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0x12/255, green: 0x12/255, blue: 0x12/255)
                .ignoresSafeArea()
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.25)
            
            WebTokenConnectWebView(onAuth: onAuth, onFail: onFail)
                .ignoresSafeArea(.keyboard)
        }
    }
}

private struct WebTokenConnectWebView: UIViewRepresentable {
    var onAuth: (String) -> Void
    var onFail: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()

        // Shim so the RN script works in WKWebView
        let shim = "window.ReactNativeWebView = window.ReactNativeWebView || { postMessage: (msg) => window.webkit?.messageHandlers?.runclub?.postMessage?.(msg) };"
        let shimScript = WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(shimScript)

        // Inject Juky script to retrieve tokens from IndexedDB and guide login flow
        let webviewURL = Config.jukyWebURL
        let scriptSource = """
          const WEBVIEW_URL = "\(webviewURL)";

          const sendMessage = (type, data) => {
            window.ReactNativeWebView.postMessage(JSON.stringify({ type, data }));
          };

          const findAllByText = (text) => {
            return Array.from(document.querySelectorAll("*")).filter((element) => {
              if (element.children.length > 0) {
                return false;
              }
              return element.textContent.trim().includes(text);
            });
          };

          document.documentElement.style.opacity = 0;
          document.documentElement.style.backgroundColor = "#121212";
          document.body.style.opacity = 0;

          // Persist data across page navigations using sessionStorage
          let silentAuthorization =
            sessionStorage.getItem("silentAuthorization") === "false" ? false : true;
          let retriesAttempts = parseInt(
            sessionStorage.getItem("retriesAttempts") ?? "2",
            10
          );

          window.addEventListener("load", async () => {
            const pageURL = new URL(window.location.href);
            // sendMessage("DEBUG_INFO", window.location.href);

            if (pageURL.host === "web.juky.app") {
              // Don't show page content
              document.documentElement.style.opacity = 0;

              // Wait for the login callback to be processed
              if (pageURL.href.includes("/login")) {
                // In case page didn't redirect
                window.setTimeout(() => {
                  window.location.href = WEBVIEW_URL;
                }, 1000);
                return;
              }

              // Try to get token from storage
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

              // Check if user just authorized in spotify page but still no token in storage - reload page once and try again
              if (!silentAuthorization) {
                sessionStorage.setItem("silentAuthorization", "true");
                silentAuthorization = true;
                window.setTimeout(() => {
                  window.location.reload();
                }, 1000);
                return;
              }

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
              sendMessage("NOT_LOGGED_IN", {});
            } else {
              // Check if user is already authorized in spotify page before, just click "authorize" automatically
              // (Lost/expired token case)
              const authAcceptElement = document.querySelector(
                '[data-testid="auth-accept"]'
              );
              if (silentAuthorization && authAcceptElement) {
                authAcceptElement.click();
                return;
              }

              document.documentElement.style.opacity = 1;
              document.body.style.opacity = 1;
              sessionStorage.setItem("silentAuthorization", "false");
              silentAuthorization = false;

              const googleLoginLink = document.querySelector('a[href*="/login/google"]');
              if (googleLoginLink) {
                googleLoginLink.style.display = "none";
              }

              const facebookLoginLink = document.querySelector(
                'a[href*="/login/facebook"]'
              );
              if (facebookLoginLink) {
                facebookLoginLink.style.display = "none";
              }

              const inputElement = document.querySelector("input");
              if (inputElement) {
                inputElement.setAttribute("name", "search");
                inputElement.setAttribute("autocomplete", "off");
              }
            }

            const signupLink =
              document.querySelector('a[href*="/login/signup"]') ??
              document.getElementById("sign-up-link");
            if (signupLink) {
              signupLink.parentElement.style.display = "none";
            }

            const termsLink = document.querySelector('a[href*="policies.google"]');
            if (termsLink) {
              termsLink.parentElement.style.pointerEvents = "none";
            }

            const replacedElements = findAllByText("Juky");
            replacedElements.forEach((element) => {
              element.innerHTML = element.innerHTML.replaceAll("Juky", "RunClub");
            });

            const recentTracksText = findAllByText('View your activity')[0] ?? findAllByText('Ver tu actividad')[0] ?? findAllByText('Voir votre activité')[0];
            if (recentTracksText) {
              const recentTracksBlock = recentTracksText.parentElement.parentElement;
              Array.from(recentTracksBlock.parentElement.children).forEach((el, index) => {
                if (el.index !== 0 && el !== recentTracksBlock) {
                  el.style.display = 'none';
                }
              });
            }

            sendMessage("NOT_LOGGED_IN", {});
          });
        """
        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        contentController.addUserScript(userScript)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.preferences.javaScriptEnabled = true
        let handler = context.coordinator.handler
        handler.onNotLoggedIn = { print("[AUTH] WebTokenConnectView.onNotLoggedIn") }
        handler.onFailAuth = { print("[AUTH] WebTokenConnectView.onFailAuth (keeping sheet open)") }
        contentController.add(handler, name: "runclub")

        let webView = NoInputAccessoryWebView(frame: .zero, configuration: config)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        
        handler.onAuth = { token in
            AuthService.setOverrideTokens(accessToken: token, refreshToken: nil, expiresAt: nil)
            print("[AUTH] WebTokenConnectView.onAuth token length=\(token.count)")
            DispatchQueue.main.async {
                webView.stopLoading()
                webView.isHidden = true
                onAuth(token)
            }
        }
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: URL(string: webviewURL)!))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // Retain handler via Coordinator to avoid deallocation
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        let handler = WebTokenMessageHandler()
    }
}
