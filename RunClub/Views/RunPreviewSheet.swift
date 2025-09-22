//
//  RunPreviewSheet.swift
//  RunClub
//

import SwiftUI
import SwiftData

struct RunPreviewSheet: View {
    let template: RunTemplateType
    let duration: DurationCategory
    var genres: [Genre] = []
    var decades: [Decade] = []
    let onContinue: (PreviewRun) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var preview: PreviewRun?
    @State private var isLoading: Bool = true
    @State private var replacingIndex: Int? = nil

    var body: some View {
        VStack(spacing: 16) {
            // Header bar
            HStack(alignment: .center) {
                Text("TODAY’S RUN")
                    .font(RCFont.medium(24))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            // Subheader: Workout Playlist + total runtime
            HStack {
                Text("Workout Playlist").font(RCFont.semiBold(17))
                Spacer()
                Text(totalRuntimeText).font(RCFont.semiBold(17))
            }
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Scrollable content (extends to bottom; extra bottom padding so last row clears CTA)
            ScrollView {
                VStack(spacing: 18) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 120) // space for CTA overlay
            }
            .scrollIndicators(.hidden)
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white, location: 0.0),
                        .init(color: .white, location: 0.80),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .padding(.bottom, 0)
        }
        .padding(.top, 20)
        .padding(.horizontal,20)
        .foregroundColor(.white)
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            // Gradient overlay + CTA pinned at bottom
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color.black, Color.black.opacity(0.0)], startPoint: .bottom, endPoint: .top)
                    .frame(height: 140)
                    .allowsHitTesting(false)
                HStack {
                    LooksGoodCTA(isEnabled: preview != nil) {
                        if let p = preview { onContinue(p) }
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .task { await loadPreview() }
    }

    @ViewBuilder private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if let p = preview {
            let slices = sectionSlices(for: p)
            if !slices.warmup.isEmpty { sectionView(title: "WARMUP", seconds: slices.warmupSeconds) { rowsView(slices.warmup) } }
            if !slices.main.isEmpty { sectionView(title: "MAIN", seconds: slices.mainSeconds) { rowsView(slices.main) } }
            if !slices.cooldown.isEmpty { sectionView(title: "COOLDOWN", seconds: slices.cooldownSeconds) { rowsView(slices.cooldown) } }
        } else {
            Text("Could not load preview.").foregroundColor(Color.white.opacity(0.4))
        }
    }

    private func loadPreview() async {
        isLoading = true
        let service = RunPreviewService(modelContext: modelContext)
        do {
            let p = try await service.buildPreview(template: template, duration: duration, genres: genres, decades: decades)
            preview = p
        } catch {
            preview = nil
        }
        isLoading = false
    }

    private func replace(at index: Int) async {
        guard let p = preview else { return }
        replacingIndex = index
        let service = RunPreviewService(modelContext: modelContext)
        do {
            let updated = try await service.replaceTrack(preview: p, at: index, genres: genres, decades: decades)
            preview = updated
        } catch {
        }
        replacingIndex = nil
    }

    private func formatMs(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Sections
    private func sectionSlices(for preview: PreviewRun) -> (warmup: [Row], main: [Row], cooldown: [Row], warmupSeconds: Int, mainSeconds: Int, cooldownSeconds: Int) {
        let gen = LocalGenerator(modelContext: modelContext)
        let counts = gen.plannedSegmentCounts(template: preview.template, durationCategory: preview.duration)
        // Build flat rows with overall index
        let rows: [Row] = preview.tracks.enumerated().map { (idx, t) in Row(index: idx + 1, track: t) }
        let wuCount = min(counts.wuSlots, rows.count)
        let mainStart = wuCount
        let mainCount = min(counts.coreSlots, max(0, rows.count - mainStart))
        let cdStart = mainStart + mainCount
        let warmup = Array(rows.prefix(wuCount))
        let main = Array(rows.dropFirst(mainStart).prefix(mainCount))
        let cooldown = Array(rows.dropFirst(cdStart))
        let ws = warmup.reduce(0) { $0 + $1.track.durationMs } / 1000
        let ms = main.reduce(0) { $0 + $1.track.durationMs } / 1000
        let cs = cooldown.reduce(0) { $0 + $1.track.durationMs } / 1000
        return (warmup, main, cooldown, ws, ms, cs)
    }

    private func sectionView<T: View>(title: String, seconds: Int, @ViewBuilder content: () -> T) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(RCFont.regular(14)).foregroundColor(Color.white.opacity(0.4))
                Spacer()
                Text(formatTotal(seconds)).font(RCFont.regular(14)).foregroundColor(Color.white.opacity(0.4))
            }
            .padding(.bottom, 8)
            content()
        }
    }

    private func rowsView(_ rows: [Row]) -> some View {
        VStack(spacing: 12) {
            ForEach(rows) { r in
                VStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("\(r.index)")
                            .font(RCFont.regular(13))
                            .foregroundColor(Color.white.opacity(0.4))
                            .frame(width: 20, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.track.title).font(RCFont.medium(16))
                            Text(r.track.artist).font(RCFont.regular(13)).foregroundColor(Color.white.opacity(0.4))
                        }
                        Spacer()
                        EffortTag(r.track.effort)
                        Button(action: { Task { await replace(at: r.index - 1) } }) {
                            Image(systemName: replacingIndex == (r.index - 1) ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                                .font(.system(size: 20, weight: .regular))
                        }
                        .disabled(replacingIndex != nil)
                    }
                    Divider()
                }
            }
        }
    }

    private func formatTotal(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if s == 0 { return "\(m)min" }
        return "\(m)m \(s)s"
    }

    private var totalRuntimeText: String {
        guard let p = preview else { return "" }
        let total = p.tracks.reduce(0) { $0 + ($1.durationMs / 1000) }
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct EffortTag: View {
    let effort: LocalGenerator.EffortTier
    init(_ e: LocalGenerator.EffortTier) { self.effort = e }
    var body: some View {
        Text(label)
            .font(RCFont.semiBold(12))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color)
            .cornerRadius(12)
    }
    private var label: String {
        switch effort { case .easy: return "EASY"; case .moderate: return "MEDIUM"; case .strong: return "STRONG"; case .hard: return "HARD"; case .max: return "MAX" }
    }
    private var color: Color {
        switch effort {
        case .easy: return Color(red: 0.0, green: 0.6, blue: 0.3)
        case .moderate: return Color(red: 0.6, green: 0.0, blue: 0.6) // magenta/purple mix
        case .strong: return Color(red: 0.4, green: 0.0, blue: 0.6) // deep purple
        case .hard: return Color(red: 0.85, green: 0.45, blue: 0.0) // orange
        case .max: return Color.red
        }
    }
}

// MARK: - Row model and CTA
private struct Row: Identifiable {
    let id = UUID()
    let index: Int
    let track: PreviewTrack
}

private struct LooksGoodCTA: View {
    var isEnabled: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("LOOKS GOOD")
                .font(RCFont.semiBold(17))
                .foregroundColor(.black)
                .padding(.horizontal, 40)
                .frame(height: 60)
                .background(Color.white)
                .cornerRadius(100)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}


