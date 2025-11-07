//
//  AuthService.swift
//  RunClub
//
//  Created by Christian Vivadelli on 8/15/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AuthService: NSObject, ObservableObject {
    @Published private(set) var isAuthorized = false
    @Published private(set) var credentials: SpotifyCredentials?

    private let storage = TokenStorage()

    // MARK: - Public lifecycle

    /// Call on app launch to restore saved credentials. Override tokens are handled lazily.
    func loadFromKeychain() {
        credentials = storage.load()
        Task { await refreshIfNeeded() }
    }

    /// Returns the most recent usable access token.
    func accessToken() async -> String? {
        await refreshIfNeeded()
        return Self.activeToken(fallback: credentials?.accessToken)
    }

    // MARK: - Refresh

    /// Ensures a valid access token is available. Prefers Juky override tokens, falls back to native credentials.
    func refreshIfNeeded() async {
        if let override = await Self.ensureOverrideToken() {
            if override.isValid {
                isAuthorized = true
                credentials = nil
                return
            }
        }

        if credentials == nil {
            credentials = storage.load()
        }

        guard let creds = credentials else {
            isAuthorized = false
            return
        }

        // Native credentials cannot be refreshed on-device without a backend token exchange.
        if creds.expiresAt <= Date().addingTimeInterval(60) {
            credentials = nil
            storage.clear()
            isAuthorized = false
            return
        }

        isAuthorized = true
    }

    // MARK: - Logout (optional helper)

    func logout() {
        credentials = nil
        storage.clear()
        Self.clearOverrideToken()
        isAuthorized = false
    }

    /// Keeps the authorization state in sync when override tokens change from outside this instance.
    fileprivate func handleOverrideChange() {
        Task { await refreshIfNeeded() }
    }
}

// (Removed: legacy sharedToken helper to avoid ambiguity)

// MARK: - Third-party override token storage (StatsForSpotify)
extension AuthService {
    private static let overrideTokenKey = "spotify_override_access_token"
    private static let overrideTokenExpiresKey = "spotify_override_access_expires_at"
    private static let overrideRefreshTokenKey = "spotify_override_refresh_token"

    /// Synchronous accessor for use in request closures.
    static func sharedTokenSync() -> String? {
        if let override = overrideState(), override.isValid { return override.token }
        return RootView.sharedAuth?.credentials?.accessToken
    }

    /// Returns an override access token if present (may be expired).
    static func overrideToken() -> String? {
        overrideState()?.token
    }

    /// Stores override tokens and optional expiry timestamp.
    static func setOverrideTokens(accessToken: String, refreshToken: String?, expiresAt: Date?) {
        Keychain.set(Data(accessToken.utf8), key: overrideTokenKey)
        if let refreshToken { Keychain.set(Data(refreshToken.utf8), key: overrideRefreshTokenKey) }
        if let expiresAt {
            Keychain.set(Data(String(expiresAt.timeIntervalSince1970).utf8), key: overrideTokenExpiresKey)
        }
        UserDefaults.standard.set(true, forKey: "has_override_token")
        RootView.sharedAuth?.handleOverrideChange()
    }

    /// Clears any override token so native credentials are used.
    static func clearOverrideToken() {
        Keychain.set(Data(), key: overrideTokenKey)
        Keychain.set(Data(), key: overrideTokenExpiresKey)
        Keychain.set(Data(), key: overrideRefreshTokenKey)
        UserDefaults.standard.set(false, forKey: "has_override_token")
        RootView.sharedAuth?.handleOverrideChange()
    }

    /// Async: returns a usable access token. Prefers override (Juky). If missing/expired, tries headless fetch.
    static func sharedToken() async -> String? {
        if let override = await ensureOverrideToken(), override.isValid { return override.token }
        return RootView.sharedAuth?.credentials?.accessToken
    }
}

// MARK: - Storage helpers
private extension AuthService {
    struct OverrideTokenState {
        let token: String
        let expiresAt: Date?

        var isValid: Bool {
            guard let expiresAt else { return true }
            return Date() < expiresAt
        }
    }

    static func activeToken(fallback: String?) -> String? {
        if let override = overrideState(), override.isValid { return override.token }
        return fallback
    }

    static func overrideState() -> OverrideTokenState? {
        guard let tokenData = Keychain.get(overrideTokenKey),
              let token = String(data: tokenData, encoding: .utf8),
              !token.isEmpty else { return nil }

        var expires: Date? = nil
        if let expData = Keychain.get(overrideTokenExpiresKey),
           let expStr = String(data: expData, encoding: .utf8),
           let interval = TimeInterval(expStr) {
            expires = Date(timeIntervalSince1970: interval)
        }

        return OverrideTokenState(token: token, expiresAt: expires)
    }

    static func ensureOverrideToken() async -> OverrideTokenState? {
        if let current = overrideState(), current.isValid { return current }
        _ = await JukyHeadlessRefresher.refreshToken()
        return overrideState()
    }

    struct TokenStorage {
        private let key = "spotify_credentials"
        private let decoder = JSONDecoder()
        private let encoder = JSONEncoder()

        func load() -> SpotifyCredentials? {
            guard let data = Keychain.get(key) else { return nil }
            return try? decoder.decode(SpotifyCredentials.self, from: data)
        }

        func save(_ credentials: SpotifyCredentials) {
            guard let data = try? encoder.encode(credentials) else { return }
            Keychain.set(data, key: key)
        }

        func clear() {
            Keychain.set(Data(), key: key)
        }
    }
}

