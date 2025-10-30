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
    var onFailAuth: (() -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "runclub" else { return }
        guard let body = message.body as? String else { return }
        print("[WebToken] message body=\(body.prefix(300))")
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = obj["type"] as? String {
            switch type {
            case "AUTH_DATA":
                if let s = obj["data"] as? String, let authData = s.data(using: .utf8) {
                    if let json = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
                       let token = json["access_token"] as? String {
                        onAuth?(token)
                    } else {
                        onFailAuth?()
                    }
                } else {
                    onFailAuth?()
                }
            case "NOT_LOGGED_IN":
                onNotLoggedIn?()
            case "FAIL_AUTH":
                // keep the sheet open; allow redirect flow to continue
                onFailAuth?()
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

        // Inject the friend's script with small additions: force logout first and poll for spAuth
        let webviewURL = "https://www.statsforspotify.com/track/recent"
        let scriptSource = """
        const WEBVIEW_URL = '\(webviewURL)';
        const sendMessage = (type, data) => {
          window.ReactNativeWebView.postMessage(JSON.stringify({type, data}));
        }
        const findAllByText = (text) => {
          return Array.from(document.querySelectorAll('*')).filter(element => {
            if (element.children.length > 0) { return false; }
            return element.textContent.trim().includes(text);
          });
        };
        // Always force a fresh Stats session once per sheet presentation
        if (!window.__RC_FORCED_LOGOUT__) {
          window.__RC_FORCED_LOGOUT__ = true;
          if (location.host === 'www.statsforspotify.com' && !location.pathname.startsWith('/logout')) {
            location.href = 'https://www.statsforspotify.com/logout';
          }
        }
        document.documentElement.style.opacity = 0;
        document.documentElement.style.backgroundColor = '#121212';
        document.body.style.opacity = 0;
        function tryEmitAuth() {
          try {
            const authData = window.localStorage.getItem('spAuth');
            if (authData) { sendMessage('AUTH_DATA', authData); return true; }
          } catch (e) {}
          return false;
        }
        window.addEventListener('load', () => {
          const pageURL = new URL(window.location.href);
          // After logout, bounce to target page
          if (pageURL.host === 'www.statsforspotify.com' && pageURL.pathname.startsWith('/logout')) {
            setTimeout(() => { window.location.href = WEBVIEW_URL; }, 600);
            return;
          }
          if (pageURL.host === 'www.statsforspotify.com') {
            document.documentElement.style.opacity = 0;
            if (!tryEmitAuth()) {
              sendMessage('FAIL_AUTH', {});
              setTimeout(() => { window.location.href = WEBVIEW_URL; }, 1000);
              return;
            }
          } else {
            document.documentElement.style.opacity = 1;
            document.body.style.opacity = 1;
            const loginForm = document.querySelector('form');
            if (loginForm) { loginForm.nextSibling && (loginForm.nextSibling.style.display = 'none'); }
            const buttonsList = document.querySelector('ul');
            if (buttonsList) { buttonsList.style.display = 'none'; }
            const separator = document.querySelector('hr');
            if (separator) { separator.style.display = 'none'; }
            const signupLink = document.querySelector('a[href*="/login/signup"]') ?? document.getElementById('sign-up-link');
            if (signupLink) { signupLink.parentElement && (signupLink.parentElement.style.display = 'none'); }
            const termsLink = document.querySelector('a[href*="policies.google"]');
            if (termsLink) { termsLink.parentElement && (termsLink.parentElement.style.pointerEvents = 'none'); }
            const replacedElements = findAllByText('Stats for Spotify');
            replacedElements.forEach(element => { element.innerHTML = element.innerHTML.replaceAll('Stats for Spotify', 'Lowkey'); });
            sendMessage('NOT_LOGGED_IN', {});
            // Poll for auth appearing after redirect completes
            let attempts = 0;
            const iv = setInterval(() => {
              attempts++;
              if (tryEmitAuth() || attempts > 150) { clearInterval(iv); }
            }, 200);
          }
        });
        """
        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        contentController.addUserScript(userScript)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.preferences.javaScriptEnabled = true
        let handler = context.coordinator.handler
        handler.onAuth = { token in
            AuthService.setOverrideToken(token, expiresAt: nil)
            onAuth(token)
        }
        handler.onNotLoggedIn = { /* no-op */ }
        handler.onFailAuth = { /* keep sheet open */ }
        contentController.add(handler, name: "runclub")

        let webView = WKWebView(frame: .zero, configuration: config)
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


