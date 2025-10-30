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

    func startLogin() { /* disabled */ }

    func handleRedirect(url: URL) { /* disabled */ }

    private func exchangeCodeForTokens(code: String) async { /* disabled */ }

    // MARK: - Refresh

    /// Refresh when <60s remaining; persists updated creds. Retries on transient server errors.
    func refreshIfNeeded() async { /* disabled */ }

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

// MARK: - Shared token helper for services needing Web API
extension AuthService {
    static func sharedToken() async -> String? {
        await MainActor.run { RootView.sharedAuth?.credentials?.accessToken }
    }
}

// MARK: - Third-party override token storage (StatsForSpotify)
extension AuthService {
    private static let overrideTokenKey = "spotify_override_access_token"
    private static let overrideTokenExpiresKey = "spotify_override_access_expires_at"

    /// Synchronous accessor for use in request closures.
    static func sharedTokenSync() -> String? {
        RootView.sharedAuth?.credentials?.accessToken
    }

    /// Returns an override access token if present (no refresh semantics).
    static func overrideToken() -> String? {
        guard let data = Keychain.get(overrideTokenKey), let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        // Optional expiry gate
        if let expData = Keychain.get(overrideTokenExpiresKey),
           let expStr = String(data: expData, encoding: .utf8),
           let interval = TimeInterval(expStr) {
            let expiresAt = Date(timeIntervalSince1970: interval)
            if Date() >= expiresAt { return nil }
        }
        return s
    }

    /// Stores an override access token and optional expiry timestamp.
    static func setOverrideToken(_ token: String, expiresAt: Date?) {
        Keychain.set(Data(token.utf8), key: overrideTokenKey)
        if let expiresAt {
            Keychain.set(Data(String(expiresAt.timeIntervalSince1970).utf8), key: overrideTokenExpiresKey)
        }
        UserDefaults.standard.set(true, forKey: "has_override_token")
    }

    /// Clears any override token so native credentials are used.
    static func clearOverrideToken() {
        Keychain.set(Data(), key: overrideTokenKey)
        Keychain.set(Data(), key: overrideTokenExpiresKey)
        UserDefaults.standard.set(false, forKey: "has_override_token")
    }
}

