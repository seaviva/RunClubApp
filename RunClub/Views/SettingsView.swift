//
//  SettingsView.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import SwiftUI
import SwiftData
import UIKit
// Dev utility
import Foundation

struct SettingsView: View {
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var crawlCoordinator: CrawlCoordinator
    @EnvironmentObject var progressStore: CrawlProgressStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("runsPerWeek") private var runsPerWeek: Int = 3
    @AppStorage("preferredDurationCategory") private var preferredDurationRaw: String = DurationCategory.medium.rawValue
    @AppStorage("onboardingComplete") private var onboardingComplete: Bool = true
    // Progress comes from global coordinator so crawl persists across navigation
    @State private var counts: (tracks: Int, features: Int, artists: Int) = (0,0,0)
    @State private var lastCompleted: Date? = nil

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Preferences")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Runs per week")
                        HStack {
                            ForEach([2,3,4,5], id: \.self) { n in
                                Button(action: { runsPerWeek = n }) {
                                    Text("\(n)")
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                        .background(runsPerWeek == n ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                    Picker("Preferred duration", selection: $preferredDurationRaw) {
                        ForEach(DurationCategory.allCases) { cat in
                            Text(cat.displayName).tag(cat.rawValue)
                        }
                    }
                    // Pace bucket stored in SwiftData (UserRunPrefs)
                    HStack {
                        Text("Pace bucket")
                        Spacer()
                        PaceBucketPicker()
                    }
                    // Cadence override (SPM)
                    CadenceOverrideRow()
                }

                Section(header: Text("Spotify")) {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(auth.isAuthorized ? "Connected" : "Not connected")
                            .foregroundColor(auth.isAuthorized ? .green : .secondary)
                    }
                    Button("Reconnect Spotify") { auth.startLogin() }
                    Button("Disconnect Spotify") { auth.logout() }
                        .foregroundColor(.red)
                }

                Section(header: Text("Library")) {
                    HStack {
                        Text("Tracks")
                        Spacer()
                        if progressStore.isRunning {
                            HStack(spacing: 6) {
                                Text(progressStore.tracksTotal > 0 ? "\(progressStore.tracksDone)/\(progressStore.tracksTotal)" : "\(progressStore.tracksDone)")
                                    .foregroundColor(.secondary)
                                ProgressView().scaleEffect(0.8)
                            }
                        } else {
                            Text("\(counts.tracks)").foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text("Features")
                        Spacer()
                        if progressStore.isRunning {
                            HStack(spacing: 6) {
                                Text("\(progressStore.featuresDone)").foregroundColor(.secondary)
                                ProgressView().scaleEffect(0.8)
                            }
                        } else {
                            Text("\(counts.features)").foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text("Artists")
                        Spacer()
                        if progressStore.isRunning {
                            HStack(spacing: 6) {
                                Text("\(progressStore.artistsDone)").foregroundColor(.secondary)
                                ProgressView().scaleEffect(0.8)
                            }
                        } else {
                            Text("\(counts.artists)").foregroundColor(.secondary)
                        }
                    }
                    if let lastCompleted { HStack { Text("Last cached"); Spacer(); Text(lastCompleted.formatted(date: .abbreviated, time: .shortened)).foregroundColor(.secondary) } }
                    if progressStore.isRunning {
                        Button("Cancel Crawl") {
                            let coord = crawlCoordinator
                            Task { await coord.cancel() }
                        }
                    } else {
                        Button("Refresh Library") {
                            // Start global refresh and keep the sheet up so user can Cancel immediately
                            let coord = crawlCoordinator
                            Task { await coord.refresh() }
                        }
                    }
                }

                Section(header: Text("App")) {
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
                    // Hidden developer: Run generator matrix (press and hold to reveal)
                    Button("Run Generator Matrix (dev)") {
                        let gen = LocalGenerator(modelContext: modelContext)
                        let spotify = SpotifyService()
                        Task {
                            if let tok = await auth.accessToken() { spotify.accessTokenProvider = { tok } }
                            var failures: [String] = []
                            var rows: [String] = []
                            var details: [String] = []
                            for template in RunTemplateType.allCases {
                                for duration in DurationCategory.allCases {
                                    do {
                                        let r = try await gen.generateDryRun(template: template,
                                                                              durationCategory: duration,
                                                                              genres: [], decades: [],
                                                                              spotify: spotify)
                                        if !(r.totalSeconds >= r.minSeconds && r.totalSeconds <= r.maxSeconds) {
                                            failures.append("bounds \(template.rawValue)-\(duration.displayName) secs=\(r.totalSeconds) range=[\(r.minSeconds),\(r.maxSeconds)]")
                                        }
                                        var perArtist: [String: Int] = [:]
                                        var backToBackOk = true
                                        for (i, aid) in r.artistIds.enumerated() {
                                            perArtist[aid, default: 0] += 1
                                            if i > 0 && r.artistIds[i-1] == aid { backToBackOk = false }
                                        }
                                        if perArtist.values.contains(where: { $0 > 2 }) { failures.append("artist-cap \(template.rawValue)-\(duration.displayName)") }
                                        if !backToBackOk { failures.append("back-to-back \(template.rawValue)-\(duration.displayName)") }
                                        let maxCount = r.efforts.filter { $0 == .max }.count
                                        if maxCount > 1 { failures.append("max-cap \(template.rawValue)-\(duration.displayName) max=\(maxCount)") }
                                        if template == .kicker {
                                            let hardCount = r.efforts.filter { $0 == .hard }.count
                                            if hardCount > 2 { failures.append("kicker-hard-cap \(duration.displayName) hard=\(hardCount)") }
                                        }
                                        rows.append("\(template.rawValue),\(duration.displayName),\(r.trackIds.count),\(r.totalSeconds)")
                                        // Append detailed lines for this run beneath the matrix in the CSV
                                        details.append("\n# \(template.rawValue) — \(duration.displayName) (tracks=\(r.trackIds.count) secs=\(r.totalSeconds) range=[\(r.minSeconds),\(r.maxSeconds)] market=\(r.market) unplayable=\(r.preflightUnplayable) swapped=\(r.swapped) removed=\(r.removed))")
                                        details.append(contentsOf: r.debugLines)
                                    } catch {
                                        failures.append("exception \(template.rawValue)-\(duration.displayName): \(error)")
                                    }
                                }
                            }
                            print("GeneratorMatrix: template,duration,tracks,seconds")
                            for r in rows { print(r) }
                            if failures.isEmpty { print("GeneratorMatrix: ALL OK") }
                            else { print("GeneratorMatrix FAILURES (\(failures.count)):\n\(failures.joined(separator: "\n"))") }
                            // Save CSV + failures to Documents
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
            .task { await loadCounts() }
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

    private func loadCounts() async {
        do {
            let tracks = try modelContext.fetch(FetchDescriptor<CachedTrack>()).count
            let feats = try modelContext.fetch(FetchDescriptor<AudioFeature>()).count
            let artists = try modelContext.fetch(FetchDescriptor<CachedArtist>()).count
            let state = try modelContext.fetch(FetchDescriptor<CrawlState>()).first
            await MainActor.run {
                counts = (tracks, feats, artists)
                lastCompleted = state?.lastCompletedAt
            }
        } catch { }
    }
}

// MARK: - UIKit activity view wrapper
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Pace bucket picker bound to SwiftData UserRunPrefs
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

// MARK: - Cadence override row
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
        .onChange(of: valueString) { _, _ in /* live editing; save on submit or reset */ }
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


