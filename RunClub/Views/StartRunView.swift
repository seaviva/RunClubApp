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
    let duration: DurationCategory

    @StateObject private var workout = WorkoutSessionManager()
    @StateObject private var orchestrator = RunOrchestrator()
    @StateObject private var spotify = SpotifyPlaybackController()

    @State private var hasStarted = false
    @State private var showSummary = false

    var body: some View {
        VStack(spacing: 16) {
            header
            metrics
            nowNext
            Spacer()
            controls
        }
        .padding(20)
        .onAppear { setupOrchestrator() }
        .sheet(isPresented: $showSummary) { summarySheet }
    }

    private var header: some View {
        HStack {
            Text("RUN SESSION")
                .font(RCFont.medium(20))
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark").imageScale(.medium)
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 24) {
            metricBox(title: "Elapsed", value: formattedTime(orchestrator.elapsedSeconds))
            metricBox(title: "Remaining", value: formattedTime(orchestrator.remainingSeconds))
            metricBox(title: "Distance", value: String(format: "%.2f mi", metersToMiles(workout.totalDistanceMeters)))
        }
    }

    private var nowNext: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOW")
                .font(RCFont.regular(13))
                .foregroundColor(.secondary)
            Text(nowTrackLine)
                .font(RCFont.semiBold(18))
            Text(nowEffortLine)
                .font(RCFont.regular(15))
                .foregroundColor(.secondary)
            if orchestrator.next != nil {
                Text(nextTrackLine)
                    .font(RCFont.regular(15))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if !hasStarted {
                Button(action: startRun) { Text("Start Run") }
                    .buttonStyle(PrimaryFilledButtonStyle())
            } else if orchestrator.isActive && !spotify.isPlaying {
                Button(action: resumeRun) { Text("Play") }
                    .buttonStyle(PrimaryFilledButtonStyle())
                Button(action: endRun) { Text("End Run") }
                    .buttonStyle(SecondaryOutlineButtonStyle())
            } else if orchestrator.isActive {
                Button(action: pauseRun) { Text("Pause") }
                    .buttonStyle(SecondaryOutlineButtonStyle())
                Button(action: endRun) { Text("End Run") }
                    .buttonStyle(PrimaryFilledColorButtonStyle(color: Color.red))
            } else {
                Button(action: endRun) { Text("Close") }
                    .buttonStyle(SecondaryOutlineButtonStyle())
            }
        }
    }

    // MARK: - Actions
    private func setupOrchestrator() {
        orchestrator.onCompleted = { endRun() }
        orchestrator.onPhaseUpdate = { _, _ in }
        spotify.onPlaybackEnded = { endRun() }
    }

    private func startRun() {
        Task {
            do {
                try await workout.requestAuthorization()
                try await workout.startRunningWorkout()
                await NotificationScheduler.shared.requestAuthorization()
                // Build phases from generator's plan; estimate 4 minutes per slot
                let gen = LocalGenerator(modelContext: modelContext)
                let slots = gen.plannedSlots(template: template, durationCategory: duration)
                let phases: [RunOrchestrator.PhaseState] = slots.enumerated().map { idx, s in
                    let name = label(for: s.effort)
                    return .init(index: idx, name: name, effort: s.effort, durationSeconds: 240)
                }
                await orchestrator.start(phases: phases)
                await spotify.playPlaylist(uri: playlistURI)
                hasStarted = true
            } catch {
                // TODO: surface error
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
            await workout.endWorkout()
            await NotificationScheduler.shared.cancelRunCues()
            showSummary = true
        }
    }

    // MARK: - Helpers
    private func metricBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(RCFont.regular(13)).foregroundColor(.secondary)
            Text(value).font(RCFont.semiBold(18))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.06))
        .cornerRadius(8)
    }

    private var nowTrackLine: String {
        if let meta = spotify.currentTrack {
            return "\(meta.title) — \(meta.artist) (\(formattedTime(meta.durationMs/1000)))"
        }
        return "Track starting…"
    }

    private var nowEffortLine: String {
        if let c = orchestrator.current { return "Effort: \(label(for: c.effort))" }
        return ""
    }

    private var nextTrackLine: String {
        if let meta = spotify.nextTrack {
            return "NEXT: \(meta.title) — \(meta.artist) (\(formattedTime(meta.durationMs/1000)))"
        }
        if let n = orchestrator.next { return "NEXT: \(n.name)" }
        return ""
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
}

// MARK: - Summary sheet
extension StartRunView {
    @ViewBuilder
    private var summarySheet: some View {
        RunSummaryView(
            template: template,
            duration: duration,
            distanceMiles: metersToMiles(workout.totalDistanceMeters),
            elapsedSeconds: orchestrator.elapsedSeconds
        )
        .overlay(alignment: .topTrailing) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark").imageScale(.medium)
            }
            .padding(16)
        }
    }
}


