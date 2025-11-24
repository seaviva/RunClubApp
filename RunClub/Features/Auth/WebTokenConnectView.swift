//
//  WebTokenConnectView.swift
//  RunClub
//
//  Created by Assistant on 10/24/25.
//

import SwiftUI
import WebKit

final class WebTokenMessageHandler: NSObject, WKScriptMessageHandler {
    var onAuth: ((String) -> Void)?
    var onNotLoggedIn: (() -> Void)?
    var onFailAuth: ((String) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "runclub" else { return }
        guard let body = message.body as? String else { return }
        print("[WebToken] message body=\(body.prefix(300))")
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
                    } else { onFailAuth?("AUTH_DATA_MISSING_ACCESS_TOKEN") }
                } else if let s = obj["data"] as? String, let authData = s.data(using: .utf8) {
                    if let json = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
                       let token = json["access_token"] as? String {
                        AuthService.setOverrideTokens(accessToken: token, refreshToken: nil, expiresAt: nil)
                        onAuth?(token)
                    } else { onFailAuth?("AUTH_DATA_INVALID_LEGACY_PAYLOAD") }
                } else { onFailAuth?("AUTH_DATA_UNRECOGNIZED_SHAPE") }
            case "NOT_LOGGED_IN":
                onNotLoggedIn?()
            case "FAIL_AUTH":
                // keep the sheet open; allow redirect flow to continue
                onFailAuth?("FAIL_AUTH")
            case "DB_ERROR":
                onFailAuth?("DB_ERROR")
            case "LOG":
                if let payload = obj["data"] {
                    print("[WebToken][LOG] \(payload)")
                }
            default:
                break
            }
        }
    }
}

struct WebTokenConnectView: UIViewRepresentable {
    var onAuth: (String) -> Void
    var onFail: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()

        // Shim so the RN script works in WKWebView
        let shim = "window.ReactNativeWebView = window.ReactNativeWebView || { postMessage: (msg) => window.webkit?.messageHandlers?.runclub?.postMessage?.(msg) };"
        let shimScript = WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(shimScript)

        // Inject Juky script to retrieve tokens from IndexedDB and guide login flow
        let webviewURL = "https://web.juky.app"
        let scriptSource = """
        const WEBVIEW_URL = '\(webviewURL)';
        const sendMessage = (type, data) => {
          window.ReactNativeWebView.postMessage(JSON.stringify({type, data}));
        };
        const findAllByText = (text) => {
          return Array.from(document.querySelectorAll('*')).filter(element => {
            if (element.children.length > 0) { return false; }
            return element.textContent.trim().includes(text);
          });
        };
        const hideDocument = () => {
          document.documentElement.style.opacity = 0;
          document.documentElement.style.backgroundColor = '#121212';
          document.body.style.opacity = 0;
        };
        const showDocument = () => {
          document.documentElement.style.opacity = 1;
          document.documentElement.style.backgroundColor = '#121212';
          document.body.style.opacity = 1;
        };
        window.__runclub = window.__runclub || {};
        window.__runclub.showDocument = showDocument;
        window.__runclub.hideDocument = hideDocument;
        hideDocument();
        window.addEventListener('load', async () => {
          const pageURL = new URL(window.location.href);
          if (pageURL.host === 'web.juky.app') {
            hideDocument();
            try {
              const db = await new Promise((resolve, reject) => {
                const request = window.indexedDB.open('SpotifyTokensDatabase');
                request.onsuccess = () => resolve(request.result);
                request.onerror = () => reject(request.error);
              });
              const storeNames = [];
              for (let i = 0; i < db.objectStoreNames.length; i += 1) {
                storeNames.push(db.objectStoreNames.item(i));
              }
              const hasSpotifyStore = (typeof db.objectStoreNames.contains === 'function' && db.objectStoreNames.contains('spotifyTokens')) ||
                storeNames.includes('spotifyTokens');
              if (hasSpotifyStore) {
                const transaction = db.transaction(['spotifyTokens']);
                const objectStore = transaction.objectStore('spotifyTokens');
                const res = await new Promise((resolve, reject) => {
                  const storeResult = objectStore.getAll();
                  storeResult.onsuccess = () => resolve(storeResult.result);
                  storeResult.onerror = () => reject(storeResult.error);
                });
                if (res.length > 0) {
                  sendMessage('AUTH_DATA', res[0]);
                  return;
                }
                sendMessage('LOG', { stage: 'spotifyTokens-empty', message: 'No entries in spotifyTokens store.' });
              } else {
                sendMessage('LOG', { stage: 'store-missing', message: 'spotifyTokens object store missing.' });
              }
            } catch (e) {
              sendMessage('LOG', { stage: 'indexeddb-error', message: (e && e.message) ? e.message : 'Unexpected IndexedDB error.' });
              showDocument();
              sendMessage('DB_ERROR', {});
              return;
            }
            const cws = findAllByText('Continue with Spotify')[0];
            if (cws) {
              cws.click();
            } else {
              sendMessage('LOG', { stage: 'cta-missing', message: 'Continue with Spotify button not found.' });
            }
            showDocument();
            sendMessage('NOT_LOGGED_IN', {});
          } else {
            showDocument();
            const loginForm = document.querySelector('form');
            if (loginForm && loginForm.nextSibling) { loginForm.nextSibling.style.display = 'none'; }
            const buttonsList = document.querySelector('ul');
            if (buttonsList) { buttonsList.style.display = 'none'; }
            const separator = document.querySelector('hr');
            if (separator) { separator.style.display = 'none'; }
            const signupLink = document.querySelector('a[href*="/login/signup"]') ?? document.getElementById('sign-up-link');
            if (signupLink && signupLink.parentElement) { signupLink.parentElement.style.display = 'none'; }
            const termsLink = document.querySelector('a[href*="policies.google"]');
            if (termsLink && termsLink.parentElement) { termsLink.parentElement.style.pointerEvents = 'none'; }
            sendMessage('NOT_LOGGED_IN', {});
          }
        });
        """
        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        contentController.addUserScript(userScript)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.preferences.javaScriptEnabled = true

        let coordinator = context.coordinator
        let handler = coordinator.handler

        // When auth succeeds, make sure we both store tokens (for legacy shapes)
        // and immediately stop/hide the web view before notifying the caller.
        handler.onAuth = { token in
            // Backward-compatible: if given a single token string
            AuthService.setOverrideTokens(accessToken: token, refreshToken: nil, expiresAt: nil)
            print("[AUTH] WebTokenConnectView.onAuth token length=\(token.count)")
            DispatchQueue.main.async {
                coordinator.webView?.stopLoading()
                coordinator.webView?.isHidden = true
                onAuth(token)
            }
        }

        handler.onNotLoggedIn = {
            print("[AUTH] WebTokenConnectView.onNotLoggedIn")
            coordinator.showDocument()
        }

        handler.onFailAuth = { reason in
            coordinator.showDocument()
            switch reason {
            case "FAIL_AUTH":
                print("[WebToken] Juky reported FAIL_AUTH; keeping session active for retry")
            default:
                print("[WebToken] Authentication failure reason=\(reason)")
                onFail()
            }
        }

        contentController.add(handler, name: "runclub")

        let webView = WKWebView(frame: .zero, configuration: config)
        coordinator.webView = webView
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: URL(string: webviewURL)!))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // Retain handler via Coordinator to avoid deallocation
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Coordinator keeps strong references to the message handler and
    /// manages convenience helpers for interacting with the underlying web view.
    final class Coordinator {
        let handler = WebTokenMessageHandler()
        weak var webView: WKWebView?

        /// Safely shows the web content once the login flow requires user interaction.
        func showDocument() {
            evaluate(js: "window.__runclub?.showDocument?.()")
        }

        /// Executes JavaScript on the managed web view and surfaces any evaluation errors.
        private func evaluate(js: String) {
            webView?.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("[WebToken] JS evaluation error=\(error)")
                }
            }
        }
    }
}


