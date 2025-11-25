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
    @State private var showLengthDropdown: Bool = false
    @State private var showPlaylistSelection: Bool = false
    
    // Track which sync type is running
    @State private var likesQuickSyncRunning: Bool = false
    @State private var likesFullResetRunning: Bool = false
    @State private var playlistsQuickSyncRunning: Bool = false
    @State private var playlistsFullResetRunning: Bool = false

    var body: some View {
        NavigationStack {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            
            // Tap-to-dismiss layer for dropdown
            if showLengthDropdown {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showLengthDropdown = false
                        }
                    }
                    .zIndex(99)
            }
            
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
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showLengthDropdown.toggle()
                                }
                            }
                            SettingsRow(label: "FILTERS", value: "NONE", showChevron: true) {
                                // TODO: Open filters picker
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if showLengthDropdown {
                                LengthDropdown(
                                    selectedMinutes: $defaultRunMinutes,
                                    isPresented: $showLengthDropdown
                                )
                                .offset(x: 0, y: 28 + 52) // 28 for section title + padding, 52 for row height
                            }
                        }
                        .zIndex(100)
                        
                        // MARK: - Songs - Likes
                        let likesRunning = progressStore.isRunning && progressStore.debugName == "LIKES"
                        SettingsSectionWithStatus(
                            title: "SONGS - LIKES",
                            statusText: likesRunning
                                ? (progressStore.message.isEmpty ? "Syncing..." : progressStore.message)
                                : (lastCompleted != nil ? "Sync'd \(lastCompleted!.formatted(date: .numeric, time: .shortened))" : "Not synced")
                        ) {
                            if likesRunning {
                                SettingsRowWithProgress(
                                    label: "TRACKS",
                                    value: progressStore.tracksTotal > 0 ? "\(progressStore.tracksDone)/\(progressStore.tracksTotal)" : "\(progressStore.tracksDone)"
                                )
                            } else {
                                SettingsRow(label: "TRACKS", value: "\(likesFeaturesCount)/\(likesCount)")
                            }
                            SettingsRowDualAction(
                                // Left button: QUICK SYNC or CANCEL (if quick sync is running)
                                leftLabel: likesQuickSyncRunning ? "CANCEL" : "QUICK SYNC",
                                leftIcon: likesQuickSyncRunning ? "x" : "ArrowsClockwise",
                                leftColor: likesQuickSyncRunning ? .red : .green,
                                leftDisabled: likesFullResetRunning,  // Disabled if OTHER sync is running
                                leftAction: {
                                    let coord = crawlCoordinator
                                    if likesQuickSyncRunning {
                                        Task { await coord.cancel() }
                                    } else {
                                        likesQuickSyncRunning = true
                                        Task { await coord.quickSync() }
                                    }
                                },
                                // Right button: FULL RESET or CANCEL (if full reset is running)
                                rightLabel: likesFullResetRunning ? "CANCEL" : "FULL RESET",
                                rightIcon: likesFullResetRunning ? "x" : "ClockClockwise",
                                rightColor: likesFullResetRunning ? .red : .blue,
                                rightDisabled: likesQuickSyncRunning,  // Disabled if OTHER sync is running
                                rightAction: {
                                    let coord = crawlCoordinator
                                    if likesFullResetRunning {
                                        Task { await coord.cancel() }
                                    } else {
                                        likesFullResetRunning = true
                                        Task { await coord.refresh() }
                                    }
                                }
                            )
                        }
                        
                        // MARK: - Songs - Playlists
                        SettingsSectionWithStatus(
                            title: "SONGS - PLAYLISTS",
                            statusText: playlistsProgress.isRunning
                                ? (playlistsProgress.message.isEmpty ? "Syncing..." : playlistsProgress.message)
                                : (playlistsLastSync != nil ? "Sync'd \(playlistsLastSync!.formatted(date: .numeric, time: .shortened))" : "Not synced")
                        ) {
                            SettingsRowNav(label: "SELECTED PLAYLISTS", value: "\(selectedPlaylistsCount)") {
                                showPlaylistSelection = true
                            }
                            
                            if playlistsProgress.isRunning {
                                SettingsRowWithProgress(
                                    label: "TRACKS",
                                    value: playlistsProgress.tracksTotal > 0 ? "\(playlistsProgress.tracksDone)/\(playlistsProgress.tracksTotal)" : "\(playlistsProgress.tracksDone)"
                                )
                            } else {
                                SettingsRow(label: "TRACKS", value: "\(playlistsFeaturesCount)/\(playlistsCount)")
                            }
                            SettingsRowDualAction(
                                // Left button: QUICK SYNC or CANCEL (if quick sync is running)
                                leftLabel: playlistsQuickSyncRunning ? "CANCEL" : "QUICK SYNC",
                                leftIcon: playlistsQuickSyncRunning ? "x" : "ArrowsClockwise",
                                leftColor: playlistsQuickSyncRunning ? .red : .green,
                                leftDisabled: playlistsFullResetRunning,  // Disabled if OTHER sync is running
                                leftAction: {
                                    if playlistsQuickSyncRunning {
                                        Task { await playlistsCoordinator.cancel() }
                                    } else {
                                        playlistsQuickSyncRunning = true
                                        Task {
                                            await MainActor.run {
                                                playlistsProgress.message = "Checking for changes…"
                                                playlistsProgress.isRunning = true
                                            }
                                            await playlistsCoordinator.configure(auth: auth, progressStore: playlistsProgress, likesContext: modelContext)
                                            await playlistsCoordinator.refreshCatalog()
                                            await playlistsCoordinator.quickSync()
                                            await loadCounts()
                                        }
                                    }
                                },
                                // Right button: FULL RESET or CANCEL (if full reset is running)
                                rightLabel: playlistsFullResetRunning ? "CANCEL" : "FULL RESET",
                                rightIcon: playlistsFullResetRunning ? "x" : "ClockClockwise",
                                rightColor: playlistsFullResetRunning ? .red : .blue,
                                rightDisabled: playlistsQuickSyncRunning,  // Disabled if OTHER sync is running
                                rightAction: {
                                    if playlistsFullResetRunning {
                                        Task { await playlistsCoordinator.cancel() }
                                    } else {
                                        playlistsFullResetRunning = true
                                        Task {
                                            await MainActor.run {
                                                playlistsProgress.message = "Full reset…"
                                                playlistsProgress.isRunning = true
                                            }
                                            await playlistsCoordinator.configure(auth: auth, progressStore: playlistsProgress, likesContext: modelContext)
                                            await playlistsCoordinator.refreshCatalog()
                                            await playlistsCoordinator.refreshSelected()
                                            await loadCounts()
                                        }
                                    }
                                }
                            )
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
        .task {
            await playlistsCoordinator.configure(auth: auth, progressStore: playlistsProgress, likesContext: modelContext)
            await loadCounts()
        }
        .onChange(of: playlistsProgress.isRunning) { running in
            if !running {
                playlistsLastSync = Date()
                playlistsQuickSyncRunning = false
                playlistsFullResetRunning = false
                Task { await loadCounts() }
            }
        }
        .onChange(of: progressStore.isRunning) { running in
            if !running {
                likesQuickSyncRunning = false
                likesFullResetRunning = false
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

/// Section with status text below (right-aligned, size 13, light font)
private struct SettingsSectionWithStatus<Content: View>: View {
    let title: String
    let statusText: String
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
            
            // Status text - right aligned, size 13, light font
            HStack {
                Spacer()
                Text(statusText)
                    .font(RCFont.light(13))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.top, 6)
        }
    }
}

/// Row with two side-by-side action buttons
private struct SettingsRowDualAction: View {
    let leftLabel: String
    var leftIcon: String? = nil
    var leftColor: Color = .green
    var leftDisabled: Bool = false
    let leftAction: () -> Void
    
    let rightLabel: String
    var rightIcon: String? = nil
    var rightColor: Color = .blue
    var rightDisabled: Bool = false
    let rightAction: () -> Void
    
    var body: some View {
        HStack(spacing: 1) {
            // Left button
            Button(action: leftAction) {
                HStack(spacing: 6) {
                    Text(leftLabel)
                        .font(RCFont.regular(16))
                    if let leftIcon {
                        Image(leftIcon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                }
                .foregroundColor(leftDisabled ? .white.opacity(0.3) : leftColor)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white.opacity(0.1))
            }
            .buttonStyle(.plain)
            .disabled(leftDisabled)
            
            // Right button
            Button(action: rightAction) {
                HStack(spacing: 6) {
                    Text(rightLabel)
                        .font(RCFont.regular(16))
                    if let rightIcon {
                        Image(rightIcon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                }
                .foregroundColor(rightDisabled ? .white.opacity(0.3) : rightColor)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white.opacity(0.1))
            }
            .buttonStyle(.plain)
            .disabled(rightDisabled)
        }
    }
}

/// Length dropdown selector
private struct LengthDropdown: View {
    @Binding var selectedMinutes: Int
    @Binding var isPresented: Bool
    
    // Range from 20 to 120 minutes in 5-minute increments
    private let minuteOptions = stride(from: 20, through: 120, by: 5).map { $0 }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(minuteOptions, id: \.self) { minutes in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedMinutes = minutes
                            isPresented = false
                        }
                    } label: {
                        HStack {
                            Text("\(minutes)")
                                .font(RCFont.regular(16))
                                .foregroundColor(.white)
                            Spacer()
                            if minutes == selectedMinutes {
                                Image("check")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    
                    // Divider between items (except after last)
                    if minutes != minuteOptions.last {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 1)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(width: 120, height: 300)
        .background(
            ZStack {
                Color.black
                Color.white.opacity(0.15)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
    }
}
