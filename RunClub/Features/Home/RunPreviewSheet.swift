//
//  RunPreviewSheet.swift
//  RunClub

import SwiftUI
import SwiftData

struct RunPreviewSheet: View {
    let template: RunTemplateType
    let runMinutes: Int
    var genres: [Genre] = []
    var decades: [Decade] = []
    let onBack: () -> Void
    let onContinue: (PreviewRun) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var preview: PreviewRun?
    @State private var isLoading: Bool = true
    @State private var replacingIndex: Int? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.horizontal, 14)
                
                // Scrollable content
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Title row
                        titleRow
                        
                        // Workout info bar
                        workoutInfoBar
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                        
                        // Track sections
                        content
                            .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 140) // Space for CTA
                }
            }
            
            // CTA overlay pinned to bottom
            VStack(spacing: 0) {
                // Gradient for fade effect
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 36)
                .allowsHitTesting(false)
                
                // Button area with solid background
                HStack {
                    StartRunCTA(isEnabled: preview != nil) {
                        if let p = preview { onContinue(p) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 34) // Safe area approximate
                .background(Color.black)
            }
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
        .task { await loadPreview() }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        ZStack {
            // Step indicator (two bars - second filled for step 2)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 34, height: 2)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 34, height: 2)
            }
            
            HStack {
                Button(action: { onBack() }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image("Xflat")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
            }
        }
        .padding(.top, 16)
    }
    
    // MARK: - Title Row
    
    private var titleRow: some View {
        HStack {
            Text("Your Run")
                .font(RCFont.medium(28))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Workout Info Bar
    
    private var workoutInfoBar: some View {
        HStack {
            Text(template.rawValue)
                .font(RCFont.medium(16))
                .foregroundColor(.white)
            Spacer()
            Text(totalRuntimeText)
                .font(RCFont.medium(16))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
        } else if let p = preview {
            let slices = sectionSlices(for: p)
            VStack(alignment: .leading, spacing: 0) {
                if !slices.warmup.isEmpty {
                    sectionView(title: "WARMUP", seconds: slices.warmupSeconds) {
                        rowsView(slices.warmup)
                    }
                }
                if !slices.main.isEmpty {
                    sectionView(title: "MAIN", seconds: slices.mainSeconds) {
                        rowsView(slices.main)
                    }
                }
                if !slices.cooldown.isEmpty {
                    sectionView(title: "COOLDOWN", seconds: slices.cooldownSeconds) {
                        rowsView(slices.cooldown)
                    }
                }
            }
        } else {
            Text("Could not load preview.")
                .foregroundColor(Color.white.opacity(0.4))
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
        }
    }

    private func loadPreview() async {
        isLoading = true
        let service = RunPreviewService(modelContext: modelContext)
        do {
            let p = try await service.buildPreview(template: template, runMinutes: runMinutes, genres: genres, decades: decades)
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

    // MARK: - Sections
    
    private func sectionSlices(for preview: PreviewRun) -> (warmup: [Row], main: [Row], cooldown: [Row], warmupSeconds: Int, mainSeconds: Int, cooldownSeconds: Int) {
        let gen = LocalGenerator(modelContext: modelContext)
        let counts = gen.plannedSegmentCounts(template: preview.template, runMinutes: preview.runMinutes)
        // Build flat rows with overall index
        let rows: [Row] = preview.tracks.enumerated().map { (idx, t) in Row(index: idx, track: t) }
        let wuCount = min(counts.wuSlots, rows.count)
        // Reserve cooldown from the end using planned cdSlots; main is the middle
        let cdCount = min(counts.cdSlots, max(0, rows.count - wuCount))
        let mainCount = max(0, rows.count - wuCount - cdCount)
        let warmup = Array(rows.prefix(wuCount))
        let main = Array(rows.dropFirst(wuCount).prefix(mainCount))
        let cooldown = Array(rows.suffix(cdCount))
        let ws = warmup.reduce(0) { $0 + $1.track.durationMs } / 1000
        let ms = main.reduce(0) { $0 + $1.track.durationMs } / 1000
        let cs = cooldown.reduce(0) { $0 + $1.track.durationMs } / 1000
        return (warmup, main, cooldown, ws, ms, cs)
    }

    private func sectionView<T: View>(title: String, seconds: Int, @ViewBuilder content: () -> T) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(RCFont.regular(14))
                    .foregroundColor(Color.white.opacity(0.4))
                Spacer()
                Text(formatSectionTime(seconds))
                    .font(RCFont.regular(14))
                    .foregroundColor(Color.white.opacity(0.4))
            }
            content()
        }
        .padding(.bottom, 20)
    }

    private func rowsView(_ rows: [Row]) -> some View {
        VStack(spacing: 16) {
            ForEach(rows) { r in
                TrackRowView(
                    track: r.track,
                    isReplacing: replacingIndex == r.index,
                    onReplace: {
                        Task { await replace(at: r.index) }
                    }
                )
            }
        }
    }

    private func formatSectionTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return "\(m)m \(s)s"
    }

    private var totalRuntimeText: String {
        guard let p = preview else { return "--m --s" }
        let total = p.tracks.reduce(0) { $0 + ($1.durationMs / 1000) }
        let m = total / 60
        let s = total % 60
        return "\(m)m \(s)s"
    }
}

// MARK: - Track Row View

private struct TrackRowView: View {
    let track: PreviewTrack
    let isReplacing: Bool
    let onReplace: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Album art
            AsyncImage(url: track.albumArtURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(Color.white.opacity(0.3))
                        )
                @unknown default:
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            
            // Track info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(RCFont.regular(16))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(RCFont.regular(13))
                    .foregroundColor(Color.white.opacity(0.4))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Effort tag with refresh button
            EffortTagButton(
                effort: track.effort,
                isLoading: isReplacing,
                onTap: onReplace
            )
        }
    }
}

// MARK: - Effort Tag Button (combined effort label + refresh)

private struct EffortTagButton: View {
    let effort: LocalGenerator.EffortTier
    let isLoading: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(color)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(color)
                }
                
                Text(label)
                    .font(RCFont.semiBold(12))
                    .foregroundColor(color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.20))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
    
    private var label: String {
        switch effort {
        case .easy: return "EASY"
        case .moderate: return "MEDIUM"
        case .strong: return "STRONG"
        case .hard: return "HARD"
        case .max: return "MAX"
        }
    }
    
    private var color: Color {
        switch effort {
        case .easy: return Color(hex: 0x00C853)
        case .moderate: return Color(hex: 0xFF18A6)
        case .strong: return Color(hex: 0x8E24AA)
        case .hard: return Color(hex: 0xFF6F00)
        case .max: return Color(hex: 0xFF3333)
        }
    }
}

// MARK: - Row model

private struct Row: Identifiable {
    let id = UUID()
    let index: Int
    let track: PreviewTrack
}

// MARK: - Start Run CTA

private struct StartRunCTA: View {
    var isEnabled: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("START RUN")
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
