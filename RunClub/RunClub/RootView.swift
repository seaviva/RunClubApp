//
//  RootView.swift
//  RunClub
//
//  Created by Christian Vivadelli on 8/15/25.
//

import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var auth: AuthService
    private let spotify = SpotifyService()

    var body: some View {
        VStack(spacing: 16) {
            Text("RunClub")
                .font(.largeTitle).bold()

            if auth.isAuthorized {
                Text("Connected to Spotify ✅")

                Button("Create Test Playlist") {
                    Task {
                        // Always fetch a fresh/valid token before calling Spotify
                        guard let token = await auth.accessToken() else { return }
                        spotify.accessTokenProvider = { token }
                        do {
                            let url = try await spotify.createSimplePlaylistFromLikes(
                                name: "RunClub · Test \(Date().formatted(date: .numeric, time: .omitted))"
                            )
                            await UIApplication.shared.open(url)
                        } catch {
                            print("Playlist error:", error)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Fetch Profile") {
                    Task { await testMe() }
                }
            } else {
                Button("Connect Spotify") { auth.startLogin() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onOpenURL { url in auth.handleRedirect(url: url) }
    }

    private func testMe() async {
        // Use refreshed token path here too
        guard let token = await auth.accessToken() else { return }
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let json = String(data: data, encoding: .utf8) ?? ""
            print("ME:", json)
        } catch {
            print("ME failed:", error)
        }
    }
}
