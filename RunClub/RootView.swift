//
//  RootView.swift
//  RunClub
//
//  Created by Christian Vivadelli on 8/15/25.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingComplete") private var onboardingComplete: Bool = false
    @AppStorage("has_override_token") private var hasOverrideToken: Bool = false
    @StateObject private var crawlCoordinator = CrawlCoordinator()
    @EnvironmentObject var progressStore: LikesProgressStore
    @StateObject private var playlistsCoordinator = PlaylistsCoordinator()
    @EnvironmentObject var playlistsProgress: PlaylistsProgressStore

    var body: some View {
        Group {
            let isAuthorizedEffective = auth.isAuthorized || hasOverrideToken
            if !isAuthorizedEffective {
                LoginSplashView()
            } else if !onboardingComplete {
                OnboardingFlowView(onDone: { onboardingComplete = true })
                    .environmentObject(playlistsCoordinator)
            } else {
                HomeView()
                    .environmentObject(crawlCoordinator)
                    .environmentObject(progressStore)
                    .environmentObject(playlistsCoordinator)
            }
        }
        .onAppear {
            progressStore.debugName = "LIKES";
            playlistsProgress.debugName = "PLAYLIST S";
            Keychain.set(Data("test".utf8), key: "spotify_override_access_token")

            // Task {
            //     let tok = await AuthService.refreshToken()
            //     print("[ROOT] sharedToken=\(tok)")
            // }
            // print("[ROOT] has_override_token=\(hasOverrideToken)")
        }
        .onChange(of: hasOverrideToken) { newVal in
            print("[AUTH] has_override_token changed -> \(newVal)")
        }
        .task(id: (auth.isAuthorized || hasOverrideToken)) {
            let isAuthorizedEffective = (auth.isAuthorized || hasOverrideToken)
            guard isAuthorizedEffective else { return }
            await crawlCoordinator.configure(auth: auth, modelContext: modelContext, progressStore: progressStore)
            await crawlCoordinator.startIfNeeded()
            // Configure playlists and start a catalog refresh (non-blocking)
            await playlistsCoordinator.configure(auth: auth, progressStore: playlistsProgress, likesContext: modelContext)
            await playlistsCoordinator.refreshCatalog()
            scheduleWeeklyPlaylistsRefresh()
        }
        .onChange(of: scenePhase) { phase in
            // Auto-resume mid-run on foreground if offsets indicate partial progress
            if phase == .active {
                Task {
                    await crawlCoordinator.startIfNeeded()
                    await playlistsCoordinator.refreshCatalog()
                }
            }
        }
    }
}

// Expose a weak shared handle so services can fetch tokens without tight coupling
extension RootView {
    static weak var sharedAuth: AuthService?
}

// MARK: - Weekly playlists refresh scheduling
extension RootView {
    private func scheduleWeeklyPlaylistsRefresh() {
        let key = "playlists_last_refresh"
        let now = Date()
        let last = UserDefaults.standard.object(forKey: key) as? Date
        let sevenDays: TimeInterval = 7 * 24 * 3600
        if last == nil || now.timeIntervalSince(last!) > sevenDays {
            Task {
                await playlistsCoordinator.refreshCatalog()
                await playlistsCoordinator.refreshSelected()
            }
            UserDefaults.standard.set(now, forKey: key)
        }
    }
}
