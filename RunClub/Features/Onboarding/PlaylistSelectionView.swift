//
//  PlaylistSelectionView.swift
//  RunClub
//
//  Presents a selectable list of playlists (incl. Recently Played) for syncing.
//

import SwiftUI
import SwiftData

struct PlaylistSelectionView: View {
    enum Mode { case onboarding, settings }
    @EnvironmentObject var playlistsCoordinator: PlaylistsCoordinator
    var mode: Mode = .settings
    var onContinue: (() -> Void)? = nil
    private var playlistsCtx: ModelContext { PlaylistsDataStack.shared.context }
    @State private var refreshToken: Int = 0
    @State private var allSelectedState: Bool = false
    @State private var showIntroOverlay: Bool = true

    private var playlists: [CachedPlaylist] {
        let all = (try? playlistsCtx.fetch(FetchDescriptor<CachedPlaylist>())) ?? []
        let sorted = all.sorted { (a, b) in
            if a.isSynthetic != b.isSynthetic { return a.isSynthetic && !b.isSynthetic }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return sorted
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    Text("SELECT PLAYLISTS")
                        .font(RCFont.medium(24))
                        .foregroundColor(.white)
                        .padding(.top, 16)
                        .padding(.horizontal, 20)
                    
                    // Select All Row
                    HStack {
                        Text("Select All")
                            .font(RCFont.medium(17))
                            .foregroundColor(.white)
                        Spacer()
                        Checkbox(
                            isOn: Binding(
                                get: { allSelectedState },
                                set: { newVal in setAllSelected(newVal) }
                            )
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    // Playlists list
                    LazyVStack(spacing: 14) {
                        ForEach(playlists, id: \.id) { p in
                            let isSelected = Binding<Bool>(
                            get: { p.selectedForSync },
                            set: { newVal in set(p.id, selected: newVal) }
                            )
                            HStack(spacing: 14) {
                                PlaylistImage(urlString: p.imageURL, isSynthetic: p.isSynthetic)
                                    .frame(width: 56, height: 56)
                                    .cornerRadius(1)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(displayName(p))
                                        .font(RCFont.medium(16))
                                        .foregroundColor(.white)
                                    Text("\(p.totalTracks) Tracks")
                                        .font(RCFont.regular(12))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                Spacer()
                                RowSelectIcon(isSelected: isSelected)
                            }
                            .padding(.horizontal, 20)
                            .contentShape(Rectangle())
                            .onTapGesture { isSelected.wrappedValue.toggle() }
                }
            }
                    .padding(.bottom, mode == .onboarding ? 120 : 20)
                }
                .padding(.top, 6)
            }
            .id(refreshToken) // force view to recompute after catalog refresh
            .scrollIndicators(.hidden)
        }
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if mode == .onboarding {
                // VStack pushes content to bottom, filling the safe area
                VStack(spacing: 0) {
                    Spacer()
                    // Gradient fades the content scrolling underneath
                    LinearGradient(colors: [Color.black, Color.black.opacity(0.0)], startPoint: .bottom, endPoint: .top)
                        .frame(height: 100)
                        .allowsHitTesting(false)
                    // Solid black area with button
                    VStack {
                        Button(action: {
                            Task {
                                await playlistsCoordinator.refreshCatalog()
                                await playlistsCoordinator.refreshSelected()
                                onContinue?()
                            }
                        }) {
                            Text("SYNC PLAYLISTS")
                                .font(RCFont.semiBold(17))
                                .foregroundColor(.black)
                                .padding(.horizontal, 40)
                                .frame(height: 60)
                                .background(Color.white)
                                .cornerRadius(100)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 32)
                    .background(Color.black)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .overlay {
            if mode == .onboarding && showIntroOverlay {
                // Native iOS blur overlay
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Color.black.opacity(0.2))
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        Text("One last thing")
                            .font(RCFont.semiBold(32))
                            .foregroundColor(.white)
                        
                        Text("Add some of your playlists you want\nto sync into the generation algorithm.")
                            .font(RCFont.regular(17))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                        
                        Text("tap to continue")
                            .font(RCFont.regular(14))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, 24)
                    }
                    .padding(.horizontal, 40)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.25)) {
                        showIntroOverlay = false
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(mode == .onboarding)
        .onAppear {
            // Ensure synthetic exists and catalog is loaded at least once
            Task {
                await playlistsCoordinator.refreshCatalog()
                // Force a UI refresh so the latest catalog is rendered
                await MainActor.run { refreshToken &+= 1 }
                await MainActor.run { recomputeAllSelected() }
            }
            // Select all by default in onboarding context
            if mode == .onboarding {
                setAllSelected(true)
            }
        }
    }

    private func displayName(_ p: CachedPlaylist) -> String {
        if p.isSynthetic { return "Recently Played" }
        return p.name
    }

    private func set(_ playlistId: String, selected: Bool) {
        if let p = try? playlistsCtx.fetch(FetchDescriptor<CachedPlaylist>(predicate: #Predicate { $0.id == playlistId })).first {
            p.selectedForSync = selected
            try? playlistsCtx.save()
            recomputeAllSelected()
        }
    }
    
    private func setAllSelected(_ selected: Bool) {
        let descriptor = FetchDescriptor<CachedPlaylist>()
        if let all = try? playlistsCtx.fetch(descriptor) {
            for p in all {
                p.selectedForSync = selected
            }
            try? playlistsCtx.save()
            allSelectedState = selected
        }
    }
    
    private func recomputeAllSelected() {
        allSelectedState = !playlists.isEmpty && playlists.allSatisfy { $0.selectedForSync }
    }
}

// MARK: - Checkbox control
private struct Checkbox: View {
    @Binding var isOn: Bool
    private let size: CGFloat = 24
    var body: some View {
        Button(action: { isOn.toggle() }) {
            // NOTE: In this design, "checkbox" is the FILLED green check (selected)
            // and "select" is the outlined box (deselected), so the mapping is inverted
            // from the asset names.
            Image(isOn ? "checkbox" : "select")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row select icon (check or plus)
private struct RowSelectIcon: View {
    @Binding var isSelected: Bool
    var body: some View {
        // Same visual mapping as the "Select All" checkbox above.
        Image(isSelected ? "checkbox" : "select")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
    }
}

// MARK: - Playlist image loader
private struct PlaylistImage: View {
    let urlString: String?
    let isSynthetic: Bool
    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }
    
    private var placeholder: some View {
        // Simple gradient placeholder (different color for synthetic "Recently Played")
        LinearGradient(
            colors: isSynthetic
            ? [Color(hex: 0xB621FE), Color(hex: 0x1FD1F9)]
            : [Color(hex: 0x3C6FFF), Color(hex: 0x2A3BE0)]
        , startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

