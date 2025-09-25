//
//  RunPreviewSheet.swift
//  RunClub
//

import SwiftUI
import SwiftData

struct RunPreviewSheet: View {
    let template: RunTemplateType
    let duration: DurationCategory
    var customMinutes: Int? = nil
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
            // Header bar (match DurationPickerSheet style)
            ZStack {
                Text("TODAY’S RUN")
                    .font(RCFont.light(15))
                    .foregroundColor(.white)
                HStack {
                    Button(action: { dismiss() }) {
                        Image("x")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    Spacer()
                    Button(action: { Task { await loadPreview() } }) {
                        Image("refresh")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh Preview")
                }
            }
            // Subheader: Workout Playlist + total runtime
            HStack {
                Text("Total Runtime").font(RCFont.semiBold(17))
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
            let p = try await service.buildPreview(template: template, duration: duration, genres: genres, decades: decades, customMinutes: customMinutes)
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
            .padding(.top, 4)
            content()
        }
    }

    private func rowsView(_ rows: [Row]) -> some View {
        VStack(spacing: 20) {
            ForEach(rows) { r in
                VStack(spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("\(r.index)")
                            .font(RCFont.regular(13))
                            .foregroundColor(Color.white.opacity(0.4))
                            .frame(width: 20, alignment: .center)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.track.title).font(RCFont.regular(16))
                            Text(r.track.artist).font(RCFont.regular(13)).foregroundColor(Color.white.opacity(0.4))
                        }
                        Spacer()
                        EffortTag(r.track.effort)
                        Button(action: { Task { await replace(at: r.index - 1) } }) {
                            Image("refresh")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundColor(Color(hex: 0x666666))
                        }
                        .disabled(replacingIndex != nil)
                    }
                }
            }
        }
    }

    private func formatTotal(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if s == 0 { return "\(m)min" }
        return "\(m)min \(s)sec"
    }

    private var totalRuntimeText: String {
        guard let p = preview else { return "" }
        let total = p.tracks.reduce(0) { $0 + ($1.durationMs / 1000) }
        return formatTotal(total)
    }
}

private struct EffortTag: View {
    let effort: LocalGenerator.EffortTier
    init(_ e: LocalGenerator.EffortTier) { self.effort = e }
    var body: some View {
        Text(label)
            .font(RCFont.semiBold(12))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.20))
            .cornerRadius(12)
    }
    private var label: String {
        switch effort { case .easy: return "EASY"; case .moderate: return "MEDIUM"; case .strong: return "STRONG"; case .hard: return "HARD"; case .max: return "MAX" }
    }
    private var color: Color {
        switch effort {
        case .easy: return Color(hex: 0x00C853)   // easy: 00C853
        case .moderate: return Color(hex: 0xFF18A6) // moderate: FF18A6
        case .strong: return Color(hex: 0x8E24AA)  // strong: 8E24AA
        case .hard: return Color(hex: 0xFF6F00)    // hard: FF6F00
        case .max: return Color(hex: 0xFF3333)     // max: FF3333
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


