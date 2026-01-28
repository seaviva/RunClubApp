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

    private static let clientId = "14be97171d404e41b4a79431a2bffbcf"

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
        print("[AUTH] sharedToken() called")
        if let tok = validOverrideToken() { return tok }
        await refreshToken()
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

    private static var refreshTask: Task<Bool?, Never>?
    
    static func refreshToken() async -> Bool? {
        // If refresh already in progress, wait for it
        if let existingTask = refreshTask {
            print("[AUTH] refreshToken() — joining existing refresh task")
            return await existingTask.value
        }
        
        print("[AUTH] refreshToken() starting new refresh task")
        
        let task = Task<Bool?, Never> {
            defer { refreshTask = nil }
            return await performRefresh()
        }
        refreshTask = task
        return await task.value
    }
    
    private static func performRefresh() async -> Bool? {
        guard let refreshToken = Keychain.get(overrideRefreshTokenKey),
              let refreshTokenString = String(data: refreshToken, encoding: .utf8),
              !refreshTokenString.isEmpty else {
            print("[AUTH] performRefresh() error: no refresh token")
            return await JukyHeadlessRefresher.refreshToken()
        }
        
        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=refresh_token&refresh_token=\(refreshTokenString)&client_id=\(clientId)".data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
               guard let accessToken = json["access_token"] as? String,
                     let newRefreshToken = json["refresh_token"] as? String else {
                print("[AUTH] performRefresh() error: no access token or refresh token: \(json)")
                return await JukyHeadlessRefresher.refreshToken()
               }
                
                // Calculate expires_at from expires_in
                var expiresAt: Date? = nil
                if let expiresIn = json["expires_in"] as? Double {
                    expiresAt = Date().addingTimeInterval(expiresIn)
                }
                
                // Save tokens to Keychain
                setOverrideTokens(accessToken: accessToken, refreshToken: newRefreshToken, expiresAt: expiresAt)
                print("[AUTH] performRefresh saved new tokens, expiresAt=\(expiresAt?.description ?? "nil")")
                return true
            }

            return await JukyHeadlessRefresher.refreshToken()
        } catch {
            print("[AUTH] performRefresh error: \(error)")
            return false
        }
    }
}

