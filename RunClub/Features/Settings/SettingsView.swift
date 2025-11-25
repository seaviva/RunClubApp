//
//  SettingsView.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import SwiftUI
import SwiftData
import Foundation

struct SettingsView: View {
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var crawlCoordinator: CrawlCoordinator
    @EnvironmentObject var progressStore: LikesProgressStore // LIKES only
    @EnvironmentObject var playlistsCoordinator: PlaylistsCoordinator
    @EnvironmentObject var playlistsProgress: PlaylistsProgressStore // PLAYLISTS
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultRunMinutes") private var defaultRunMinutes: Int = 30
    @AppStorage("onboardingComplete") private var onboardingComplete: Bool = true
    // Progress comes from global coordinator so crawl persists across navigation
    @State private var likesCount: Int = 0
    @State private var likesFeaturesCount: Int = 0
    @State private var recommendedCount: Int = 0
    @State private var playlistsCount: Int = 0
    @State private var playlistsFeaturesCount: Int = 0
    @State private var selectedPlaylistsCount: Int = 0
    @State private var lastCompleted: Date? = nil
    @State private var playlistsLastSync: Date? = nil
    @State private var showStatsConnect: Bool = false
    @State private var showDurationPicker: Bool = false
    @State private var showPlaylistSelection: Bool = false

    var body: some View {
        NavigationStack {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Text("SETTINGS")
                    .font(RCFont.light(14))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // MARK: - Default Preferences
                        SettingsSection(title: "DEFAULT PREFERENCES") {
                            SettingsRow(label: "LENGTH", value: "\(defaultRunMinutes) MIN", showChevron: true) {
                                showDurationPicker = true
                            }
                            SettingsRow(label: "FILTERS", value: "NONE", showChevron: true) {
                                // TODO: Open filters picker
                            }
                        }
                        
                        // MARK: - Songs - Likes
                        SettingsSection(title: "SONGS - LIKES") {
                            let likesRunning = progressStore.isRunning && progressStore.debugName == "LIKES"
                            if likesRunning {
                                // Show tracksDone during sync for real-time feedback (matches toast)
                                SettingsRowWithProgress(
                                    label: "TRACKS",
                                    value: progressStore.tracksTotal > 0 ? "\(progressStore.tracksDone)/\(progressStore.tracksTotal)" : "\(progressStore.tracksDone)"
                                )
                                SettingsRowWithAction(
                                    label: progressStore.message.isEmpty ? "Syncing..." : progressStore.message,
                                    actionLabel: "CANCEL",
                                    actionIcon: "x",
                                    isCancel: true
                                ) {
                                    let coord = crawlCoordinator
                                    Task { await coord.cancel() }
                                }
                            } else {
                                // Show enriched count when idle (featuresDone from DB)
                                SettingsRow(label: "TRACKS", value: "\(likesFeaturesCount)/\(likesCount)")
                                SettingsRowWithAction(
                                    label: lastCompleted != nil ? "Sync'd \(lastCompleted!.formatted(date: .numeric, time: .shortened))" : "Not synced",
                                    actionLabel: "REFRESH",
                                    actionIcon: "refresh",
                                    isCancel: false
                                ) {
                                    let coord = crawlCoordinator
                                    Task { await coord.refresh() }
                                }
                            }
                        }
                        
                        // MARK: - Songs - Playlists
                        SettingsSection(title: "SONGS - PLAYLISTS") {
                            SettingsRowNav(label: "SELECTED PLAYLISTS", value: "\(selectedPlaylistsCount)") {
                                showPlaylistSelection = true
                            }
                            
                            if playlistsProgress.isRunning {
                                // Show tracksDone during sync for real-time feedback (matches toast)
                                SettingsRowWithProgress(
                                    label: "TRACKS",
                                    value: playlistsProgress.tracksTotal > 0 ? "\(playlistsProgress.tracksDone)/\(playlistsProgress.tracksTotal)" : "\(playlistsProgress.tracksDone)"
                                )
                                SettingsRowWithAction(
                                    label: playlistsProgress.message.isEmpty ? "Syncing..." : playlistsProgress.message,
                                    actionLabel: "CANCEL",
                                    actionIcon: "x",
                                    isCancel: true
                                ) {
                                    Task { await playlistsCoordinator.cancel() }
                                }
                            } else {
                                // Show enriched count when idle (featuresDone from DB)
                                SettingsRow(label: "TRACKS", value: "\(playlistsFeaturesCount)/\(playlistsCount)")
                                SettingsRowWithAction(
                                    label: playlistsLastSync != nil ? "Sync'd \(playlistsLastSync!.formatted(date: .numeric, time: .shortened))" : "Not synced",
                                    actionLabel: "REFRESH",
                                    actionIcon: "refresh",
                                    isCancel: false
                                ) {
                                    Task {
                                        print("[SETTINGS] Sync Selected tapped")
                                        await MainActor.run {
                                            playlistsProgress.message = "Starting playlists sync…"
                                            playlistsProgress.isRunning = true
                                        }
                                        await playlistsCoordinator.configure(auth: auth, progressStore: playlistsProgress, likesContext: modelContext)
                                        await playlistsCoordinator.refreshCatalog()
                                        await playlistsCoordinator.refreshSelected()
                                        await loadCounts()
                                    }
                                }
                            }
                        }
                        
                        // MARK: - App
                        SettingsSection(title: "APP") {
                            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                               let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                                SettingsRow(label: "VERSION", value: "\(version) (\(build))")
                            }
                            
                            let isConnected = auth.isAuthorized || (AuthService.overrideToken() != nil)
                            SettingsRow(label: "SPOTIFY", value: isConnected ? "CONNECTED" : "NOT CONNECTED", valueColor: isConnected ? .green : nil)
                            
                            if isConnected {
                                SettingsRowButton(label: "LOGOUT / DISCONNECT SPOTIFY", isDestructive: true) {
                                    auth.logout()
                                    AuthService.clearOverrideToken()
                                }
                            } else {
                                SettingsRowButton(label: "CONNECT VIA JUKY") {
                                    showStatsConnect = true
                                }
                            }
                        }
                        
                        // MARK: - Dev
                        SettingsSection(title: "DEV") {
                            SettingsRowButton(label: "RESET ONBOARDING") {
                                onboardingComplete = false
                            }
                            SettingsRowButton(label: "RELOAD THIRD SOURCE") {
                                ThirdSourceStoreSeeder.markForceReload()
                                playlistsProgress.message = "Third source will reload on next launch"
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showStatsConnect) {
            WebTokenConnectView(onAuth: { _ in
                showStatsConnect = false
            }, onFail: {
                // keep sheet open; user may continue
            })
        }
        .sheet(isPresented: $showDurationPicker) {
            DurationPickerSheet(initialMinutes: defaultRunMinutes) { newValue in
                if let minutes = newValue {
                    defaultRunMinutes = minutes
                }
            }
            .presentationDetents([.height(300)])
        }
        .task {
            await playlistsCoordinator.configure(auth: auth, progressStore: playlistsProgress, likesContext: modelContext)
            await loadCounts()
        }
        .onChange(of: playlistsProgress.isRunning) { running in
            if !running {
                playlistsLastSync = Date()
                Task { await loadCounts() }
            }
        }
        .onChange(of: progressStore.isRunning) { running in
            if !running {
                Task { await loadCounts() }
            }
        }
        .navigationDestination(isPresented: $showPlaylistSelection) {
            PlaylistSelectionView()
        }
        }
    }

    private func loadCounts() async {
        do {
            let tracks = try modelContext.fetch(FetchDescriptor<CachedTrack>()).count
            let features = try modelContext.fetch(FetchDescriptor<AudioFeature>()).count
            let playlistsCtx = PlaylistsDataStack.shared.context
            let plCount = try playlistsCtx.fetch(FetchDescriptor<CachedTrack>()).count
            let plFeatures = try playlistsCtx.fetch(FetchDescriptor<AudioFeature>()).count
            let selCount = try playlistsCtx.fetch(FetchDescriptor<CachedPlaylist>(predicate: #Predicate { $0.selectedForSync == true })).count
            let state = try modelContext.fetch(FetchDescriptor<CrawlState>()).first
            await MainActor.run {
                likesCount = tracks
                likesFeaturesCount = features
                recommendedCount = 0
                playlistsCount = plCount
                playlistsFeaturesCount = plFeatures
                selectedPlaylistsCount = selCount
                lastCompleted = state?.lastCompletedAt
                // If playlists have been synced but we don't have a date, show a placeholder
                if playlistsLastSync == nil && plFeatures > 0 {
                    playlistsLastSync = Date()
                }
            }
        } catch { }
    }
}

// MARK: - Settings Components

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(RCFont.light(13))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 8)
            
            VStack(alignment: .leading, spacing: 1) {
                content
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct SettingsRow: View {
    let label: String
    var value: String? = nil
    var valueColor: Color? = nil
    var showChevron: Bool = false
    var action: (() -> Void)? = nil
    
    var body: some View {
        let content = HStack {
            Text(label)
                .font(RCFont.regular(16))
                .foregroundColor(.white)
            Spacer()
            if let value {
                Text(value)
                    .font(RCFont.regular(16))
                    .foregroundColor(valueColor ?? .white.opacity(0.5))
            }
            if showChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

private struct SettingsRowNav: View {
    let label: String
    let value: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(RCFont.regular(16))
                    .foregroundColor(.white)
                Spacer()
                Text(value)
                    .font(RCFont.regular(16))
                    .foregroundColor(.white.opacity(0.5))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.1))
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsRowWithProgress: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(RCFont.regular(16))
                .foregroundColor(.white)
            Spacer()
            HStack(spacing: 8) {
                Text(value)
                    .font(RCFont.regular(16))
                    .foregroundColor(.white.opacity(0.5))
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
    }
}

private struct SettingsRowWithAction: View {
    let label: String
    let actionLabel: String
    var actionIcon: String? = nil
    var isCancel: Bool = false
    let action: () -> Void
    
    private var actionColor: Color { isCancel ? .red : .blue }
    
    var body: some View {
        HStack {
            Text(label)
                .font(RCFont.regular(16))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Button(action: action) {
                HStack(spacing: 6) {
                    Text(actionLabel)
                        .font(RCFont.regular(16))
                        .foregroundColor(actionColor)
                    if let actionIcon {
                        Image(actionIcon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundColor(actionColor)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
    }
}

private struct SettingsRowButton: View {
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(RCFont.regular(16))
                    .foregroundColor(isDestructive ? .red : .white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.1))
        }
        .buttonStyle(.plain)
    }
}
