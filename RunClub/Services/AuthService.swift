//
//  AuthService.swift
//  RunClub
//
//  Created by Christian Vivadelli on 8/15/25.
//

import Foundation
import SwiftUI
import CryptoKit
import Combine
import AuthenticationServices
import UIKit

@MainActor
final class AuthService: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var credentials: SpotifyCredentials?

    private var codeVerifier = ""
    private var authSession: ASWebAuthenticationSession?

    // MARK: - Public lifecycle

    /// Call on app launch to restore saved credentials.
    func loadFromKeychain() {
        if let data = Keychain.get("spotify_credentials"),
           let creds = try? JSONDecoder().decode(SpotifyCredentials.self, from: data) {
            self.credentials = creds
            self.isAuthorized = true
        }
    }

    /// Get a valid access token (refreshes if expiring soon).
    func accessToken() async -> String? {
        await refreshIfNeeded()
        return credentials?.accessToken
    }

    // MARK: - Login (PKCE)

    func startLogin() {
        codeVerifier = Self.randomString(64)
        let challenge = Self.codeChallenge(for: codeVerifier)

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: Config.clientID),
            .init(name: "redirect_uri", value: Config.redirectURI),
            .init(name: "scope", value: Config.scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: UUID().uuidString)
        ]

        let url = comps.url!
        authSession = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "runclub"
        ) { [weak self] cbURL, _ in
            guard let self, let cbURL else { return }
            self.handleRedirect(url: cbURL)
        }
        authSession?.prefersEphemeralWebBrowserSession = true
        authSession?.presentationContextProvider = self
        authSession?.start()
    }

    func handleRedirect(url: URL) {
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else { return }
        Task { await exchangeCodeForTokens(code: code) }
    }

    private func exchangeCodeForTokens(code: String) async {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(Config.redirectURI)",
            "client_id=\(Config.clientID)",
            "code_verifier=\(codeVerifier)"
        ].joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            struct TokenRes: Decodable { let access_token: String; let refresh_token: String; let expires_in: Double }
            let t = try JSONDecoder().decode(TokenRes.self, from: data)
            let creds = SpotifyCredentials(
                accessToken: t.access_token,
                refreshToken: t.refresh_token,
                expiresAt: Date().addingTimeInterval(t.expires_in)
            )
            self.credentials = creds
            self.isAuthorized = true
            if let encoded = try? JSONEncoder().encode(creds) {
                Keychain.set(encoded, key: "spotify_credentials")
            }
        } catch {
            print("Token exchange failed:", error)
        }
    }

    // MARK: - Refresh

    /// Refresh when <60s remaining; persists updated creds.
    func refreshIfNeeded() async {
        guard var creds = credentials else { return }
        let timeLeft = creds.expiresAt.timeIntervalSinceNow
        guard timeLeft < 60 else { return }

        do {
            var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
            req.httpMethod = "POST"
            req.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = [
                "grant_type=refresh_token",
                "refresh_token=\(creds.refreshToken)",
                "client_id=\(Config.clientID)"
            ].joined(separator: "&")
            req.httpBody = body.data(using: .utf8)

            struct RefreshRes: Decodable { let access_token: String; let expires_in: Double }
            let (data, _) = try await URLSession.shared.data(for: req)
            let r = try JSONDecoder().decode(RefreshRes.self, from: data)

            creds.accessToken = r.access_token
            creds.expiresAt = Date().addingTimeInterval(r.expires_in)
            self.credentials = creds
            if let encoded = try? JSONEncoder().encode(creds) {
                Keychain.set(encoded, key: "spotify_credentials")
            }
        } catch {
            print("Refresh failed:", error)
        }
    }

    // MARK: - Logout (optional helper)

    func logout() {
        self.credentials = nil
        self.isAuthorized = false
        Keychain.set(Data(), key: "spotify_credentials") // clears stored value
    }

    // MARK: - PKCE helpers

    private static func randomString(_ len: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<len).compactMap { _ in chars.randomElement() })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - ASWebAuthenticationSession presentation

extension AuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        return scene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

