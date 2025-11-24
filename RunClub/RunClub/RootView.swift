//
//  RootView.swift
//  RunClub
//
//  Created by Christian Vivadelli on 8/15/25.
//

import SwiftUI
import UIKit
import SwiftData

struct RootView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingComplete") private var onboardingComplete: Bool = false
    @AppStorage("has_override_token") private var hasOverrideToken: Bool = false
    @StateObject private var crawlCoordinator = CrawlCoordinator()
    @EnvironmentObject var progressStore: LikesProgressStore
    @State private var showCompletionToast: Bool = false
    @State private var completionText: String = ""
    // Add recommendations coordinator + use shared progress from environment
    // Recommendations removed
    // Playlists
    @StateObject private var playlistsCoordinator = PlaylistsCoordinator()
    @EnvironmentObject var playlistsProgress: PlaylistsProgressStore
    // Toast dismissal state (does not cancel the job)
    @State private var hideLikesToast: Bool = false
    @State private var hideRecsToast: Bool = false
    @State private var hidePlaylistsToast: Bool = false

    var body: some View {
        Group {
            let isAuthorizedEffective = auth.isAuthorized || hasOverrideToken
            if !isAuthorizedEffective {
                LoginSplashView()
            } else if !onboardingComplete {
                OnboardingFlowView(onDone: { onboardingComplete = true })
                    .environmentObject(playlistsCoordinator)
            } else {
                ZStack(alignment: .top) {
                    HomeView()
                        .environmentObject(crawlCoordinator)
                        .environmentObject(progressStore)
                        .environmentObject(playlistsCoordinator)
                }
                // Overlay the toast(s) without affecting layout; allow swipe-to-hide
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        if progressStore.isRunning && !hideLikesToast {
                            CrawlToast(title: "Syncing liked songs…", progress: progressStore, onCancel: {
                                Task { await crawlCoordinator.cancel() }
                            }, onDismiss: { hideLikesToast = true })
                            .onAppear { print("[LIKES_TOAST] running=\(progressStore.isRunning) done=\(progressStore.tracksDone) total=\(progressStore.tracksTotal) id=\(ObjectIdentifier(progressStore))") }
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if playlistsProgress.isRunning && !hidePlaylistsToast {
                            CrawlToast(title: "Syncing playlists…", progress: playlistsProgress, onCancel: {
                                Task { await playlistsCoordinator.cancel() }
                            }, onDismiss: { hidePlaylistsToast = true })
                            .onAppear { print("[PL_TOAST] running=\(playlistsProgress.isRunning) done=\(playlistsProgress.tracksDone) total=\(playlistsProgress.tracksTotal) id=\(ObjectIdentifier(playlistsProgress))") }
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if showCompletionToast && !(progressStore.isRunning) {
                            CompletionToast(text: completionText)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 12)
                    .animation(.easeInOut, value: progressStore.isRunning)
                    .animation(.easeInOut, value: playlistsProgress.isRunning)
                }
            }
        }
        .onAppear { progressStore.debugName = "LIKES"; playlistsProgress.debugName = "PLAYLISTS" }
        .onChange(of: hasOverrideToken) { newVal in
            print("[AUTH] has_override_token changed -> \(newVal)")
        }
        // Recommendations removed
        .task(id: (auth.isAuthorized || hasOverrideToken)) {
            let isAuthorizedEffective = (auth.isAuthorized || hasOverrideToken)
            guard isAuthorizedEffective else { return }
            await crawlCoordinator.configure(auth: auth, modelContext: modelContext, progressStore: progressStore)
            await crawlCoordinator.startIfNeeded()
            // Recommendations path removed
            // Configure playlists and start a catalog refresh (non-blocking)
            await playlistsCoordinator.configure(auth: auth, progressStore: playlistsProgress, likesContext: modelContext)
            await playlistsCoordinator.refreshCatalog()
            scheduleWeeklyPlaylistsRefresh()
            // Recommendations refresh scheduling removed
        }
        .onChange(of: progressStore.isRunning) { running in
            if running { hideLikesToast = false }
            if !running {
                Task {
                    let count = (try? modelContext.fetch(FetchDescriptor<CachedTrack>()).count) ?? 0
                    await MainActor.run {
                        completionText = "Library cached: \(count) tracks"
                        withAnimation { showCompletionToast = true }
                    }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run { withAnimation { showCompletionToast = false } }
                }
            }
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

private struct CrawlToast: View {
    var title: String = "Syncing liked songs…"
    @ObservedObject var progress: CrawlProgressStore
    let onCancel: () -> Void
    let onDismiss: () -> Void
    @State private var offsetY: CGFloat = 0
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RCFont.medium(14))
                if !progress.message.isEmpty {
                    Text(progress.message)
                        .font(RCFont.regular(12))
                        .foregroundColor(.white.opacity(0.7))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.tracksTotal > 0 ? "Tracks \(progress.tracksDone)/\(progress.tracksTotal)" : "Tracks \(progress.tracksDone)")
                    if progress.featuresDone > 0 || progress.artistsDone > 0 {
                        HStack(spacing: 8) {
                            if progress.featuresDone > 0 {
                                Text("Features \(progress.featuresDone)")
                            }
                            if progress.artistsDone > 0 {
                                Text("• Artists \(progress.artistsDone)")
                            }
                        }
                    }
                }
                .font(RCFont.regular(13))
                .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            Button(action: { onCancel() }) {
                Text("Cancel")
                    .font(RCFont.medium(15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white, lineWidth: 1)
                    )
            }
        }
        .padding(12)
        .background(Color.blue.opacity(1.0))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .offset(y: offsetY)
        .gesture(
            DragGesture().onChanged { value in
                // Allow dragging up to hide
                if value.translation.height < 0 { offsetY = value.translation.height }
            }.onEnded { value in
                if value.translation.height < -30 {
                    withAnimation { offsetY = -200 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
                } else {
                    withAnimation { offsetY = 0 }
                }
            }
        )
    }
}

private struct CompletionToast: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text(text)
                .font(RCFont.medium(14))
            Spacer()
        }
        .padding(12)
        .background(Color.black.opacity(0.8))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
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
