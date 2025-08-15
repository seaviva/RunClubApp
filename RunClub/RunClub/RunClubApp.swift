//
//  RunClubApp.swift
//  RunClub
//
//  Created by Christian Vivadelli on 8/15/25.
//

import SwiftUI
import SwiftData

@main
struct RunClubApp: App {
    @StateObject private var auth = AuthService()
    private let spotify = SpotifyService() // keep for future injection

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .task {
                    // Restore saved Spotify credentials and refresh if needed
                    auth.loadFromKeychain()
                    await auth.refreshIfNeeded()
                }
        }
    }
}
