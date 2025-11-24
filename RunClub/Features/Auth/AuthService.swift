//
//  AuthService.swift
//  RunClub
//
//  Created by Christian Vivadelli on 8/15/25.
//

import Foundation
import SwiftUI
import Combine
import UIKit

@MainActor
final class AuthService: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var credentials: SpotifyCredentials?

    // Native PKCE removed; use Juky override token instead

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

    // MARK: - Login
    // Native PKCE removed. Use WebTokenConnectView (Juky) to establish override tokens.

    // MARK: - Refresh

    /// Refresh when <60s remaining; persists updated creds. Retries on transient server errors.
    func refreshIfNeeded() async { /* disabled */ }

    // MARK: - Logout (optional helper)

    func logout() {
        self.credentials = nil
        self.isAuthorized = false
        Keychain.set(Data(), key: "spotify_credentials") // clears stored value
    }

    // MARK: - Legacy helpers removed
}

// (ASWebAuthenticationSession removed)

// (Removed: legacy sharedToken helper to avoid ambiguity)

// MARK: - Third-party override token storage (StatsForSpotify)
extension AuthService {
    private static let overrideTokenKey = "spotify_override_access_token"
    private static let overrideTokenExpiresKey = "spotify_override_access_expires_at"
    private static let overrideRefreshTokenKey = "spotify_override_refresh_token"

    /// Synchronous accessor for use in request closures.
    static func sharedTokenSync() -> String? {
        RootView.sharedAuth?.credentials?.accessToken
    }

    /// Returns an override access token if present (may be expired).
    static func overrideToken() -> String? {
        guard let data = Keychain.get(overrideTokenKey), let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    /// Stores override tokens and optional expiry timestamp.
    static func setOverrideTokens(accessToken: String, refreshToken: String?, expiresAt: Date?) {
        print("[AUTH] setOverrideTokens called. exp=\(expiresAt?.description ?? "nil") refresh=\(refreshToken != nil)")
        Keychain.set(Data(accessToken.utf8), key: overrideTokenKey)
        if let refreshToken { Keychain.set(Data(refreshToken.utf8), key: overrideRefreshTokenKey) }
        if let expiresAt {
            Keychain.set(Data(String(expiresAt.timeIntervalSince1970).utf8), key: overrideTokenExpiresKey)
        }
        UserDefaults.standard.set(true, forKey: "has_override_token")
        print("[AUTH] has_override_token=true")
    }

    /// Clears any override token so native credentials are used.
    static func clearOverrideToken() {
        print("[AUTH] clearOverrideToken")
        Keychain.set(Data(), key: overrideTokenKey)
        Keychain.set(Data(), key: overrideTokenExpiresKey)
        Keychain.set(Data(), key: overrideRefreshTokenKey)
        UserDefaults.standard.set(false, forKey: "has_override_token")
        print("[AUTH] has_override_token=false")
    }

    /// Async: returns a usable access token. Prefers override (Juky). If missing/expired, tries headless fetch.
    static func sharedToken() async -> String? {
        print("[AUTH] sharedToken() begin")
        if let tok = validOverrideToken() { return tok }
        _ = await JukyHeadlessRefresher.refreshToken()
        if let tok = validOverrideToken() { return tok }
        // fallback to any native creds if present
        return RootView.sharedAuth?.credentials?.accessToken
    }

    private static func validOverrideToken() -> String? {
        guard let s = Keychain.get(overrideTokenKey).flatMap({ String(data: $0, encoding: .utf8) }), !s.isEmpty else { return nil }
        if let expData = Keychain.get(overrideTokenExpiresKey),
           let expStr = String(data: expData, encoding: .utf8), let interval = TimeInterval(expStr) {
            let expiresAt = Date(timeIntervalSince1970: interval)
            if Date() >= expiresAt { return nil }
        }
        return s
    }
}

