//
//  SettingsView.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import SwiftUI
import SwiftData
import UIKit
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

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Preferences")) {
                    Picker("Default run length", selection: $defaultRunMinutes) {
                        ForEach(Array(stride(from: 20, through: 90, by: 5)), id: \.self) { m in
                            Text("\(m) min").tag(m)
                        }
                    }
                    HStack {
                        Text("Pace bucket")
                        Spacer()
                        PaceBucketPicker()
                    }
                    CadenceOverrideRow()
                }

                Section(header: Text("Spotify")) {
                    HStack {
                        Text("Status")
                        Spacer()
                        let isConnected = auth.isAuthorized || (AuthService.overrideToken() != nil)
                        Text(isConnected ? "Connected" : "Not connected")
                            .foregroundColor(isConnected ? .green : .secondary)
                    }
                    if (auth.isAuthorized || (AuthService.overrideToken() != nil)) {
                        Button("Disconnect Spotify") {
                            auth.logout()
                            AuthService.clearOverrideToken()
                        }
                        .foregroundColor(.red)
                    } else {
                        Button("Connect via Juky") { showStatsConnect = true }
                        .sheet(isPresented: $showStatsConnect) {
                            WebTokenConnectView(onAuth: { _ in
                                showStatsConnect = false
                            }, onFail: {
                                // keep sheet open; user may continue
                            })
                        }
                    }
                }

                // Data Source: Likes
                Section(header: Text("Data Source: Likes")) {
                    HStack {
                        Text("Likes")
                        Spacer()
                        if progressStore.isRunning && progressStore.debugName == "LIKES" {
                            HStack(spacing: 6) {
                                Text(progressStore.tracksTotal > 0 ? "\(progressStore.featuresDone)/\(progressStore.tracksTotal)" : "\(progressStore.featuresDone)")
                                    .foregroundColor(.secondary)
                                ProgressView().scaleEffect(0.8)
                            }
                        } else {
                            Text("\(likesFeaturesCount)/\(likesCount)").foregroundColor(.secondary)
                        }
                    }
                    Button((progressStore.isRunning && progressStore.debugName == "LIKES") ? "Cancel Likes" : "Refresh Likes") {
                        if progressStore.isRunning && progressStore.debugName == "LIKES" {
                            let coord = crawlCoordinator
                            Task { await coord.cancel() }
                        } else {
                            let coord = crawlCoordinator
                            Task { await coord.refresh() }
                        }
                    }
                    let dur = UserDefaults.standard.double(forKey: "likesIngestDurationSec")
                    let tps = UserDefaults.standard.double(forKey: "likesIngestTPS")
                    if dur > 0 {
                        HStack {
                            Text("Likes ingest")
                            Spacer()
                            Text("\(Int(dur))s • \(String(format: "%.2f", tps)) t/s")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let lastCompleted { HStack { Text("Last cached (Likes)"); Spacer(); Text(lastCompleted.formatted(date: .abbreviated, time: .shortened)).foregroundColor(.secondary) } }
                }

                // Data Source: Playlists
                Section(header: Text("Data Source: Playlists")) {
                    NavigationLink {
                        PlaylistSelectionView()
                    } label: {
                        HStack {
                            Text("Selected playlists")
                            Spacer()
                            Text("\(selectedPlaylistsCount)").foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text("Songs (playlists)")
                        Spacer()
                        if playlistsProgress.isRunning {
                            HStack(spacing: 6) {
                                Text(playlistsProgress.tracksTotal > 0 ? "\(playlistsProgress.featuresDone)/\(playlistsProgress.tracksTotal)" : "\(playlistsProgress.featuresDone)")
                                    .foregroundColor(.secondary)
                                ProgressView().scaleEffect(0.8)
                            }
                        } else {
                            Text("\(playlistsFeaturesCount)/\(playlistsCount)").foregroundColor(.secondary)
                        }
                    }
                    if playlistsProgress.isRunning {
                        Text(playlistsProgress.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button(playlistsProgress.isRunning ? "Cancel Sync" : "Sync Selected") {
                        if playlistsProgress.isRunning {
                            Task { await playlistsCoordinator.cancel() }
                        } else {
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

                Section(header: Text("App")) {
                    Button("Reload Third Source from Bundle") {
                        ThirdSourceStoreSeeder.markForceReload()
                        playlistsProgress.message = "Third source will reload on next launch"
                    }
                    Button("Reset Onboarding") { onboardingComplete = false }
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                       let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text("\(version) (\(build))")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Button("Run Generator Matrix (dev)") {
                        let gen = LocalGenerator(modelContext: modelContext)
                        let spotify = SpotifyService()
                        Task {
                            if let tok = await auth.accessToken() { spotify.accessTokenProvider = { tok } }
                            var failures: [String] = []
                            var rows: [String] = []
                            var details: [String] = []
                            for template in RunTemplateType.allCases {
                                for minutes in [20, 30, 45, 60] {
                                    do {
                                        let r = try await gen.generateDryRun(template: template,
                                                                              runMinutes: minutes,
                                                                              genres: [], decades: [],
                                                                              spotify: spotify)
                                        if !(r.totalSeconds >= r.minSeconds && r.totalSeconds <= r.maxSeconds) {
                                            failures.append("bounds \(template.rawValue)-\(minutes) mins secs=\(r.totalSeconds) range=[\(r.minSeconds),\(r.maxSeconds)]")
                                        }
                                        var perArtist: [String: Int] = [:]
                                        var backToBackOk = true
                                        for (i, aid) in r.artistIds.enumerated() {
                                            perArtist[aid, default: 0] += 1
                                            if i > 0 && r.artistIds[i-1] == aid { backToBackOk = false }
                                        }
                                        if perArtist.values.contains(where: { $0 > 2 }) { failures.append("artist-cap \(template.rawValue)-\(minutes)") }
                                        if !backToBackOk { failures.append("back-to-back \(template.rawValue)-\(minutes)") }
                                        rows.append("\(template.rawValue),\(minutes),\(r.trackIds.count),\(r.totalSeconds)")
                                        details.append("\n# \(template.rawValue) — \(minutes) min (tracks=\(r.trackIds.count) secs=\(r.totalSeconds) range=[\(r.minSeconds),\(r.maxSeconds)] market=\(r.market) unplayable=\(r.preflightUnplayable) swapped=\(r.swapped) removed=\(r.removed))")
                                        details.append(contentsOf: r.debugLines)
                                    } catch {
                                        failures.append("exception \(template.rawValue)-\(minutes): \(error)")
                                    }
                                }
                            }
                            print("GeneratorMatrix: template,duration,tracks,seconds")
                            for r in rows { print(r) }
                            if failures.isEmpty { print("GeneratorMatrix: ALL OK") }
                            else { print("GeneratorMatrix FAILURES (\(failures.count)):\n\(failures.joined(separator: "\n"))") }
                            let header = "template,duration,tracks,seconds"
                            var csv = ([header] + rows).joined(separator: "\n")
                            if !failures.isEmpty {
                                csv += "\n\nFAILURES (\(failures.count))\n" + failures.joined(separator: "\n")
                            }
                            if !details.isEmpty {
                                csv += "\n\nDETAILS\n" + details.joined(separator: "\n")
                            }
                            let df = DateFormatter()
                            df.dateFormat = "yyyyMMdd_HHmmss"
                            let filename = "GeneratorMatrix_\(df.string(from: Date())).csv"
                            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                                let url = docs.appendingPathComponent(filename)
                                do {
                                    try csv.write(to: url, atomically: true, encoding: .utf8)
                                    print("GeneratorMatrix: saved to \(url.path)")
                                    await MainActor.run {
                                        shareURL = url
                                        showShare = true
                                    }
                                } catch {
                                    print("GeneratorMatrix: save failed: \(error)")
                                }
                            }
                        }
                    }
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await playlistsCoordinator.configure(auth: auth, progressStore: playlistsProgress, likesContext: modelContext)
                await loadCounts()
            }
            .onChange(of: playlistsProgress.isRunning) { running in
                if !running {
                    Task { await loadCounts() }
                }
            }
            .onChange(of: progressStore.isRunning) { running in
                if !running {
                    Task { await loadCounts() }
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = shareURL {
                    ActivityView(activityItems: [url])
                } else {
                    Text("No report to share")
                }
            }
        }
    }

    // Share sheet state
    @State private var shareURL: URL? = nil
    @State private var showShare: Bool = false
    @State private var showStatsConnect: Bool = false

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
            }
        } catch { }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct PaceBucketPicker: View {
    @Environment(\.modelContext) private var modelContext
    @State private var current: PaceBucket = .B

    var body: some View {
        Menu(currentLabel) {
            ForEach([PaceBucket.A, .B, .C, .D], id: \.self) { bucket in
                Button(bucketLabel(bucket)) { set(bucket) }
            }
        }
        .onAppear { load() }
    }

    private var currentLabel: String {
        switch current {
        case .A: return "> 11:00 / mi"
        case .B: return "9:30–11:00 / mi"
        case .C: return "8:00–9:30 / mi"
        case .D: return "< 8:00 / mi"
        }
    }

    private func bucketLabel(_ b: PaceBucket) -> String { (b == current ? "• " : "") + currentLabelFor(b) }
    private func currentLabelFor(_ b: PaceBucket) -> String {
        switch b {
        case .A: return "> 11:00 / mi"
        case .B: return "9:30–11:00 / mi"
        case .C: return "8:00–9:30 / mi"
        case .D: return "< 8:00 / mi"
        }
    }

    private func load() {
        if let prefs = try? modelContext.fetch(FetchDescriptor<UserRunPrefs>()).first {
            current = prefs.paceBucket
        } else {
            let prefs = UserRunPrefs(paceBucket: .B)
            modelContext.insert(prefs)
            try? modelContext.save()
            current = .B
        }
    }

    private func set(_ b: PaceBucket) {
        if let prefs = try? modelContext.fetch(FetchDescriptor<UserRunPrefs>()).first {
            prefs.paceBucket = b
            try? modelContext.save()
            current = b
        } else {
            let prefs = UserRunPrefs(paceBucket: b)
            modelContext.insert(prefs)
            try? modelContext.save()
            current = b
        }
    }
}

private struct CadenceOverrideRow: View {
    @Environment(\.modelContext) private var modelContext
    @State private var valueString: String = ""
    @State private var current: Double? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                Text("Cadence (SPM)")
                Text(currentLabel).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("auto", text: $valueString)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                .onSubmit { save() }
            Button("Reset") { reset() }
        }
        .onAppear { load() }
        .onChange(of: valueString) { _, _ in }
    }

    private var currentLabel: String {
        if let cur = current { return "Using \(Int(cur)) SPM" }
        return "Auto from pace bucket"
    }

    private func load() {
        if let prefs = try? modelContext.fetch(FetchDescriptor<UserRunPrefs>()).first {
            current = prefs.customCadenceSPM
            valueString = prefs.customCadenceSPM.map { String(Int($0)) } ?? ""
        }
    }

    private func save() {
        guard let prefs = try? modelContext.fetch(FetchDescriptor<UserRunPrefs>()).first else { return }
        if let v = Double(valueString), v > 80, v < 220 {
            prefs.customCadenceSPM = v
            try? modelContext.save()
            current = v
        }
    }

    private func reset() {
        guard let prefs = try? modelContext.fetch(FetchDescriptor<UserRunPrefs>()).first else { return }
        prefs.customCadenceSPM = nil
        try? modelContext.save()
        current = nil
        valueString = ""
    }
}
