//
//  StartRunView.swift
//  RunClub
//
//  In-app run screen: start/pause/end controls, distance, time, and track/effort labels.
//

import SwiftUI
import SwiftData

struct StartRunView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let playlistURI: String
    let template: RunTemplateType
    let runMinutes: Int
    var onCompleted: ((Int, Double) -> Void)? = nil
    var onDiscarded: (() -> Void)? = nil

    @StateObject private var workout = RunSessionManager()
    @StateObject private var orchestrator = RunOrchestrator()
    @StateObject private var spotify = SpotifyPlaybackController()

    @State private var hasStarted = false
    @State private var showSummary = false
    @State private var showPlaybackAlert = false

    var body: some View {
        VStack(spacing: 16) {
            header
                .padding(.horizontal, 12)
            nowPlayingCard
                .padding(.horizontal, 8)
            nextPanel
                .padding(.horizontal, 8)
            Spacer()
            bottomBar
                .padding(.horizontal, 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .onAppear { setupOrchestrator(); Task { await spotify.warmUpPlaybackContext(uri: playlistURI, foregroundIfNeeded: false) } }
        .sheet(isPresented: $showSummary) {
            summarySheet
                .presentationDetents([.large])
        }
        .interactiveDismissDisabled(true)
        .onChange(of: spotify.playbackError) { _, newVal in
            showPlaybackAlert = (newVal != nil)
        }
        .alert("Playback Issue", isPresented: $showPlaybackAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(spotify.playbackError ?? "Unknown error")
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 10) {
            let isLive = orchestrator.isActive && spotify.isPlaying
            let dotColor: Color = isLive ? Color(hex: 0xFF3333) : Color.white.opacity(0.3)
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .shadow(color: isLive ? Color(hex: 0xFF3333) : .clear, radius: isLive ? 8 : 0)
                .animation(.easeInOut(duration: 0.2), value: isLive)
            Text("RUN")
                .font(RCFont.medium(24))
            Spacer()
        }
        .padding(.bottom, 12)
    }

    private var nowPlayingCard: some View {
        let planned = plannedEfforts
        let fallbackEffort = planned.first ?? .easy
        let color = effortColor(for: orchestrator.current?.effort ?? fallbackEffort)
        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let url = spotify.currentImageURL {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(color.opacity(0.20))
                        }
                    } else {
                        Rectangle().fill(color.opacity(0.20))
                    }
                }
                .aspectRatio(1, contentMode: .fill)
                .clipped()

                // Top gradient to improve text legibility over artwork
                LinearGradient(
                    colors: [Color.black.opacity(0.55), Color.black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .frame(maxWidth: .infinity, alignment: .top)
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 4) {
                    if let meta = spotify.currentTrack {
                        Text(meta.artist)
                            .font(RCFont.regular(14))
                            .foregroundColor(Color.white.opacity(0.6))
                        Text(meta.title)
                            .font(RCFont.medium(18))
                            .foregroundColor(.white)
                    } else {
                        Text("")
                            .font(RCFont.regular(14))
                        Text("Loading…")
                            .font(RCFont.semiBold(18))
                            .foregroundColor(.white)
                    }
                }
                .padding(16)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CURRENT")
                        .font(RCFont.regular(13))
                        .foregroundColor(Color.white.opacity(0.6))
                    Text(label(for: orchestrator.current?.effort ?? fallbackEffort).uppercased())
                        .font(RCFont.medium(36))
                        .foregroundColor(color)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(sectionLabel(for: orchestrator.current?.index ?? 0).uppercased())
                        .font(RCFont.regular(13))
                        .foregroundColor(Color.white.opacity(0.6))
                    Text(trackRemainingString)
                        .font(RCFont.medium(36))
                        .foregroundColor(.white)
                }
            }
            .padding(16)
            .background(color.opacity(0.20))
        }
        .clipShape(RoundedRectangle(cornerRadius: 1))
        .overlay(
            RoundedRectangle(cornerRadius: 1)
                .stroke(color, lineWidth: 1.5)
        )
        .shadow(color: color.opacity(0.6), radius: 18, x: 0, y: 0)
    }

    private var nextPanel: some View {
        let planned = plannedEfforts
        let nextFallbackEffort: LocalGenerator.EffortTier? = {
            guard planned.count > 1 else { return planned.first }
            return planned.dropFirst().first
        }()
        let color = effortColor(for: orchestrator.next?.effort ?? nextFallbackEffort)
        return HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("NEXT")
                    .font(RCFont.regular(13))
                    .foregroundColor(Color.white.opacity(0.4))
                Text(nextEffortText)
                    .font(RCFont.medium(17))
                    .foregroundColor(color)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(sectionLabel(for: orchestrator.next?.index ?? 1).uppercased())
                    .font(RCFont.regular(13))
                    .foregroundColor(Color.white.opacity(0.4))
                Text(nextTrackDurationString)
                    .font(RCFont.medium(17))
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(1)
    }

    private var bottomBar: some View {
        ZStack {
            HStack(alignment: .center) {
                if orchestrator.isActive && !spotify.isPlaying { // paused state: show trash on left
                    Button(action: discardRun) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Color(red: 1.0, green: 0.2, blue: 0.2))
                    }
                    .buttonStyle(CircularIconButtonStyle(diameter: 52, fillColor: Color.white.opacity(0.08), iconColor: Color(red: 1.0, green: 0.2, blue: 0.2)))
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedTime(orchestrator.elapsedSeconds))
                            .font(RCFont.semiBold(18))
                            .foregroundColor(.white)
                        let total = orchestrator.elapsedSeconds + orchestrator.remainingSeconds
                        Text(formattedTime(total))
                            .font(RCFont.regular(14))
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                }
                Spacer()
                if orchestrator.isActive && !spotify.isPlaying { // paused state: show stop on right
                    Button(action: stopRunNow) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Color(hex: 0xFFB300))
                    }
                    .buttonStyle(CircularIconButtonStyle(diameter: 52, fillColor: Color.white.opacity(0.08), iconColor: Color(hex: 0xFFB300)))
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(format: "%.2f", metersToMiles(workout.totalDistanceMeters)))
                            .font(RCFont.semiBold(18))
                            .foregroundColor(.white)
                        Text("MILES")
                            .font(RCFont.regular(14))
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                }
            }

            // Center control button (stays centered regardless of side content width)
            Group {
                if !hasStarted {
                    Button(action: startRun) { Text("START RUN") }
                        .buttonStyle(SecondaryOutlineButtonStyle())
                } else if orchestrator.isActive && spotify.isPlaying {
                    Button(action: pauseRun) { Image(systemName: "pause.fill").font(.system(size: 22, weight: .bold)) }
                        .buttonStyle(CircularIconButtonStyle(diameter: 60, fillColor: .white, iconColor: .black))
                } else if orchestrator.isActive {
                    Button(action: resumeRun) { Image(systemName: "play.fill").font(.system(size: 22, weight: .bold)) }
                        .buttonStyle(CircularIconButtonStyle(diameter: 60, fillColor: .white, iconColor: .black))
                } else {
                    Button(action: { showSummary = true }) { Text("VIEW SUMMARY") }
                        .buttonStyle(SecondaryOutlineButtonStyle())
                }
            }
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions
    private func setupOrchestrator() {
        orchestrator.onCompleted = { endRun() }
        orchestrator.onPhaseUpdate = { _, _ in }
        spotify.onPlaybackEnded = { endRun() }
        // Wire up track change detection for debugging/logging
        spotify.onTrackChanged = { [weak orchestrator] newTrackId in
            print("[SYNC] Spotify track changed to: \(newTrackId ?? "nil")")
            // Could add logic here to verify orchestrator phase alignment
        }
        // Preload playlist head so the UI shows first/next before starting
        Task { await spotify.preloadPlaylistHead(uri: playlistURI) }
    }

    private func startRun() {
        Task {
            do {
                try await workout.requestAuthorization()
                try await workout.startRunning()
                
                // Request notification authorization and log result
                let notifAuthorized = await NotificationScheduler.shared.requestAuthorization()
                if !notifAuthorized {
                    print("[RUN] Notification authorization denied - phase cues will not be delivered")
                }
                
                // Build phases aligned to actual playlist tracks to keep effort synced with music
                let durations = await fetchPlaylistTrackDurations()
                let efforts = plannedEfforts
                let count = min(efforts.count, durations.count)
                let phases: [RunOrchestrator.PhaseState] = (0..<count).map { idx in
                    let e = efforts[idx]
                    let name = label(for: e)
                    return .init(index: idx, name: name, effort: e, durationSeconds: max(1, durations[idx]))
                }
                
                print("[RUN] Starting run with \(phases.count) phases, total duration: \(phases.map { $0.durationSeconds }.reduce(0, +))s")
                
                // Ensure playback is activated and started before orchestrator to keep cues aligned
                await spotify.ensureActiveDeviceAndPlay(uri: playlistURI)
                if spotify.isPlaying {
                    await orchestrator.start(phases: phases)
                    hasStarted = true
                } else {
                    print("[RUN] Spotify playback did not start - cannot begin run")
                }
            } catch {
                print("[RUN] Failed to start run: \(error)")
            }
        }
    }

    private func pauseRun() {
        orchestrator.pause()
        workout.pause()
        spotify.pause()
    }

    private func resumeRun() {
        orchestrator.resume()
        workout.resume()
        spotify.resume()
    }

    private func endRun() {
        Task {
            spotify.stop()
            await orchestrator.stop()
            await workout.end()
            await NotificationScheduler.shared.cancelRunCues()
            showSummary = true
            onCompleted?(orchestrator.elapsedSeconds, workout.totalDistanceMeters)
        }
    }

    private func discardRun() {
        Task {
            spotify.stop()
            await orchestrator.stop()
            await NotificationScheduler.shared.cancelRunCues()
            workout.cancel()
            onDiscarded?()
            dismiss()
        }
    }

    private func stopRunNow() {
        // Save current progress and go to summary
        endRun()
    }

    // MARK: - Helpers
    private func effortColor(for tier: LocalGenerator.EffortTier?) -> Color {
        switch tier ?? .easy {
        case .easy: return Color(hex: 0x00C853)   // easy: 00C853
        case .moderate: return Color(hex: 0xFF18A6) // moderate: FF18A6
        case .strong: return Color(hex: 0x8E24AA)  // strong: 8E24AA
        case .hard: return Color(hex: 0xFF6F00)    // hard: FF6F00
        case .max: return Color(hex: 0xFF3333)     // max: FF3333
        }
    }

    private var nextEffortText: String {
        if let effort = orchestrator.next?.effort { return label(for: effort).uppercased() }
        if plannedEfforts.count > 1 { return label(for: plannedEfforts[1]).uppercased() }
        if let first = plannedEfforts.first { return label(for: first).uppercased() }
        return ""
    }

    private var nextTrackDurationString: String {
        if let nx = spotify.nextTrack { return formattedTime(nx.durationMs / 1000) }
        return "0:00"
    }

    private var trackRemainingString: String {
        if let cur = spotify.currentTrack {
            let remainingMs = max(0, cur.durationMs - spotify.currentTrackProgressMs)
            return formattedTime(remainingMs / 1000)
        }
        return "0:00"
    }

    private func label(for tier: LocalGenerator.EffortTier) -> String {
        switch tier {
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .strong: return "Strong"
        case .hard: return "Hard"
        case .max: return "Max"
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func metersToMiles(_ meters: Double) -> Double { meters / 1609.34 }

    // Planned effort tiers for template/duration to power pre-start UI defaults
    private var plannedEfforts: [LocalGenerator.EffortTier] {
        let gen = LocalGenerator(modelContext: modelContext)
        return gen.plannedSlots(template: template, runMinutes: runMinutes).map { $0.effort }
    }

    // Fetch durations (in seconds) for tracks in the created playlist to align orchestrator phases
    private func fetchPlaylistTrackDurations() async -> [Int] {
        guard let playlistId = extractPlaylistId(from: playlistURI) else { return [] }
        var durations: [Int] = []
        var next: String? = "https://api.spotify.com/v1/playlists/\(playlistId)/tracks?fields=items(track(duration_ms)),next&limit=100"
        while let urlStr = next, let url = URL(string: urlStr) {
            var req = URLRequest(url: url)
            if let token = await AuthService.sharedToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            guard let (data, response) = try? await URLSession.shared.data(for: req), (response as? HTTPURLResponse)?.statusCode == 200 else { break }
            struct Page: Decodable {
                struct Item: Decodable { struct Track: Decodable { let duration_ms: Int? }; let track: Track? }
                let items: [Item]
                let next: String?
            }
            if let page = try? JSONDecoder().decode(Page.self, from: data) {
                durations += page.items.compactMap { ($0.track?.duration_ms ?? 0) / 1000 }
                next = page.next
            } else { break }
        }
        return durations
    }

    private func extractPlaylistId(from uri: String) -> String? {
        if uri.hasPrefix("spotify:playlist:") { return uri.components(separatedBy: ":").last }
        if uri.contains("open.spotify.com/playlist/") {
            if let id = uri.split(separator: "/").last?.split(separator: "?").first { return String(id) }
        }
        return nil
    }
}

// MARK: - Summary sheet
extension StartRunView {
    // Derive phase section label (Warmup/Main/Cooldown) from a phase index
    private func sectionLabel(for index: Int?) -> String {
        guard let idx = index else { return "" }
        let gen = LocalGenerator(modelContext: modelContext)
        let counts = gen.plannedSegmentCounts(template: template, runMinutes: runMinutes)
        if idx < counts.wuSlots { return "Warmup" }
        if idx < (counts.wuSlots + counts.coreSlots) { return "Main" }
        return "Cooldown"
    }
    @ViewBuilder
    private var summarySheet: some View {
        RunSummaryView(
            template: template,
            runMinutes: runMinutes,
            distanceMiles: metersToMiles(workout.totalDistanceMeters),
            elapsedSeconds: orchestrator.elapsedSeconds
        )
        .overlay(alignment: .topTrailing) {
            Button(action: {
                onDiscarded?() // Clear "Continue Run" state
                dismiss()
            }) {
                Image(systemName: "xmark").imageScale(.medium)
            }
            .padding(16)
        }
    }
}


