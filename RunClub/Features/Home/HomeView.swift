//
//  HomeView.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var crawlCoordinator: CrawlCoordinator
    @EnvironmentObject var progressStore: LikesProgressStore
    @EnvironmentObject var playlistsCoordinator: PlaylistsCoordinator
    @EnvironmentObject var playlistsProgress: PlaylistsProgressStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("defaultRunMinutes") private var defaultRunMinutes: Int = 30
    @State private var customTemplate: RunTemplateType?
    
    @State private var customGenres: Set<Genre> = []
    @State private var customDecades: Set<Decade> = []
    @State private var customPrompt: String = ""
    @State private var customMinutes: Int? = nil
    // Track if user has explicitly changed filters this session (to override defaults)
    @State private var userChangedFilters: Bool = false
    // Carousel selection for templates on Home
    @State private var selectedTemplate: RunTemplateType = .easyRun
    // New sheets for filters and duration
    @State private var showingFiltersSheet = false
    @State private var showingDurationSheet = false
    @State private var showingSettings = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isGenerating = false
    // Current-session generated playlist URL
    @State private var generatedURL: URL? = nil
    @State private var currentUserId: String? = nil
    @State private var showingStartRun = false
    @State private var showingPreview = false
    @State private var lastGeneratedTemplate: RunTemplateType? = nil
    @State private var lastRunMinutes: Int? = nil
    @State private var pendingTemplate: RunTemplateType? = nil
    
    private let spotify = SpotifyService()
    @State private var showingLog: Bool = false

    // Order templates for the Home carousel.
    private func templateCarouselOrder(recommended: RunTemplateType?) -> [RunTemplateType] {
        let base = RunTemplateType.allCases
        guard let rec = recommended else { return base }
        return [rec] + base.filter { $0 != rec }
    }

    private var runMinutes: Int { customMinutes ?? defaultRunMinutes }

    var body: some View {
        let activeTemplate: RunTemplateType? = selectedTemplate
        GeometryReader { proxy in
        ZStack(alignment: .top) {
            // Background image keyed by carousel-selected template or rest
            Image(templateBackgroundAssetName(for: activeTemplate))
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                //Color.clear.frame(height: max(0,proxy.safeAreaInsets.top - 16))
                // Header: centered HStack with left logo, middle title, right log button
                HStack(spacing: 0) {
                    Image("runclublogo")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .frame(width: 44, height: 44, alignment: .center)

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        Button { showingLog = true } label: {
                            Image("ClockCounterClockwise")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.white)
                        }
                        .frame(width: 44, height: 44, alignment: .center)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)

                        Button { showingSettings = true } label: {
                            if progressStore.isRunning || playlistsProgress.isRunning {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.9)
                            } else {
                                Image("Gear1")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 44, height: 44, alignment: .center)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .frame(height: 44, alignment: .center)

                // Main content fills remaining space; bottom-centered
                if (AuthService.overrideToken() != nil) {
                VStack(spacing: 20) {
                        // Carousel of templates/rest (only when not completed)
                        TabView(selection: $selectedTemplate) {
                            ForEach(templateCarouselOrder(recommended: nil)) { t in
                                VStack(spacing: 12) {
                                    Text(t.rawValue)
                                        .font(RCFont.powerGroteskLight(60))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .padding(.horizontal, 20)
                                    Text(runDescription(for: t))
                                        .font(RCFont.light(16))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .lineSpacing(6)
                                        .padding(.horizontal, 20)
                                        .padding(.bottom, 24)
                                    // Duration text removed; length is now shown in the duration pill
                                }
                                .tag(t)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .padding(.bottom, 32)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .onChange(of: selectedTemplate) { _, _ in }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 16)
                } else {
                    // Use StatsForSpotify connect instead of native PKCE
                    Button("Connect Spotify") { showingSettings = true }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 32)
                }

                // Bottom controls: buttons bar + CTA, pinned to bottom
                VStack(spacing: 0) {
                    // Buttons bar (filters + duration)
                    if (AuthService.overrideToken() != nil) {
                            HStack(spacing: 16) {
                                Spacer()
                                let filtersApplied = !customGenres.isEmpty || !customDecades.isEmpty
                                Button(action: { showingFiltersSheet = true }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "music.note.list").font(.system(size: 16, weight: .regular))
                                        Text(filtersApplied ? "CUSTOM" : "AUTO")
                                            .font(RCFont.medium(15))
                                    }
                                    .foregroundColor(Color(hex: 0x1FCBFF))
                                    .padding(.horizontal, 20)
                                    .frame(height: 48)
                                    .background(Color(hex: 0x33B1FF, alpha: 0.25))
                                    .cornerRadius(28)
                                }
                                Button(action: { showingDurationSheet = true }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "timer").font(.system(size: 16, weight: .regular))
                                        let label = "~\(runMinutes)min"
                                        Text(label).font(RCFont.medium(15))
                                    }
                                    .foregroundColor(Color(hex: 0xFF3333))
                                    .padding(.horizontal, 20)
                                    .frame(height: 48)
                                    .background(Color(hex: 0xFF3333, alpha: 0.25))
                                    .cornerRadius(28)
                                }
                                Spacer()
                            }
                            .frame(height: 68)
                    }

                    // CTA row
                    
                    if (AuthService.overrideToken() != nil) {
                        HStack(spacing: 16) {
                            Spacer()
                            Button(action: {
                                if generatedURL != nil {
                                    showingStartRun = true
                                } else {
                                    let template = selectedTemplate
                                    print("Home: starting preview — template=\(template.rawValue) minutes=\(runMinutes)")
                                    pendingTemplate = template
                                    showingPreview = true
                                }
                            }) {
                                Text("LET’S RUN")
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .buttonStyle(SecondaryOutlineButtonStyle())
                            .disabled(isGenerating)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 8)
                    } else { EmptyView() }
                    Spacer()
                }
                .frame(height: 206 + max(0, proxy.safeAreaInsets.bottom))
                .padding(.horizontal, 20)
            }
            .onAppear {
                // Load default filters if user hasn't explicitly changed them this session
                if !userChangedFilters {
                    let defaultGenres = DefaultFiltersHelper.getDefaultGenres()
                    let defaultDecades = DefaultFiltersHelper.getDefaultDecades()
                    if !defaultGenres.isEmpty || !defaultDecades.isEmpty {
                        customGenres = defaultGenres
                        customDecades = defaultDecades
                    }
                }
                
                Task {
                    if let token = await auth.accessToken() {
                        spotify.accessTokenProvider = { token }
                        if let uid = try? await spotify.currentUserId() {
                            currentUserId = uid
                        }
                    }
                }
            }
        }
        }
        // Sheets
        .sheet(isPresented: $showingFiltersSheet) {
            FilterPickerSheet(initialGenres: customGenres, initialDecades: customDecades) { g, d in
                customGenres = g
                customDecades = d
                userChangedFilters = true  // Mark that user has explicitly changed filters
            }
            .presentationDetents([.large])
        }
         .sheet(isPresented: $showingDurationSheet) {
            DurationPickerSheet(initialMinutes: customMinutes) { minutes in
                customMinutes = minutes
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(auth)
                .environmentObject(crawlCoordinator)
                .environmentObject(progressStore)
                .environmentObject(playlistsCoordinator)
                .environmentObject(playlistsProgress)
        }
        .sheet(isPresented: $showingLog) { RunLogView().environment(\.modelContext, modelContext) }
        .sheet(isPresented: $showingPreview) {
            RunPreviewSheet(template: selectedTemplate, runMinutes: runMinutes, genres: Array(customGenres), decades: Array(customDecades)) { preview in
                Task { await confirm(preview: preview) }
            }
            .presentationDetents([.large])
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showingStartRun) {
            if let url = generatedURL,
               let t = lastGeneratedTemplate,
               let m = lastRunMinutes {
                StartRunView(playlistURI: url.absoluteString, template: t, runMinutes: m) { elapsedSeconds, distanceMeters in
                    persistCompletedRun(template: t, runMinutes: m, elapsedSeconds: elapsedSeconds, distanceMeters: distanceMeters)
                }
                    .presentationDetents([.large])
                    .interactiveDismissDisabled(true)
                    .presentationDragIndicator(.hidden)
            } else {
                Text("No run available")
            }
        }
        .alert("Generation failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func generate() {
        Task {
            isGenerating = true
            defer { isGenerating = false }
            // New flow: compute selection and present preview; no network playlist creation here
            let template = selectedTemplate
            pendingTemplate = template
            showingPreview = true
        }
    }

    private func confirm(preview: PreviewRun) async {
            // Use override-first provider to support StatsForSpotify login fully
            spotify.accessTokenProvider = { AuthService.overrideToken() ?? (AuthService.sharedTokenSync() ?? "") }
            do {
            let url = try await spotify.createConfirmedPlaylist(from: preview)
            generatedURL = url
            lastGeneratedTemplate = preview.template
            lastRunMinutes = preview.runMinutes
            // Clear custom minutes after successful confirmation so it only applies to this run
            customMinutes = nil
            showingPreview = false
            showingStartRun = true
            } catch {
            errorMessage = (error as NSError).localizedDescription
            showError = true
        }
    }

    private func persistCompletedRun(template: RunTemplateType, runMinutes: Int, elapsedSeconds: Int, distanceMeters: Double) {
        guard let uid = currentUserId else { return }
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd"
        let dateKey = df.string(from: Date())
        let record = CompletedRun(userId: uid, dateKey: dateKey, completedAt: Date(), elapsedSeconds: elapsedSeconds, distanceMeters: distanceMeters, template: template.rawValue, runMinutes: runMinutes)
        modelContext.insert(record)
        try? modelContext.save()
    }
    private func openURL(_ url: URL) { Task { await UIApplication.shared.open(url) } }

    private func selectionSummary() -> String {
        let hasTemplate = (customTemplate != nil)
        let hasDuration = (customMinutes != nil)
        let hasGenres = !customGenres.isEmpty
        let hasDecades = !customDecades.isEmpty
        let hasPrompt = !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !(hasTemplate || hasDuration || hasGenres || hasDecades || hasPrompt) {
            return "Auto"
        }
        var parts: [String] = []
        if let t = customTemplate { parts.append(t.rawValue) }
        if let m = customMinutes { parts.append("~\(m)min") }
        if hasGenres { parts.append("Genres: " + customGenres.map { $0.rawValue }.joined(separator: ", ")) }
        if hasDecades { parts.append("Decades: " + customDecades.map { $0.rawValue }.joined(separator: ", ")) }
        if hasPrompt { parts.append("Prompt: \(customPrompt)") }
        return parts.joined(separator: " · ")
    }

    private func filterSummary() -> String {
        var parts: [String] = []
        if !customGenres.isEmpty { parts.append(customGenres.map { $0.rawValue }.joined(separator: ", ")) }
        if !customDecades.isEmpty { parts.append(customDecades.map { $0.rawValue }.joined(separator: ", ")) }
        let prompt = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty { parts.append("\"\(prompt)\"") }
        return parts.joined(separator: " • ")
    }

    private func runDescription(for template: RunTemplateType) -> String {
        switch template {
        case .easyRun:
            return "A relaxed, steady-paced run with low-energy tracks to keep you comfortable from start to finish. Perfect for recovery or getting moving without pushing too hard."
        case .strongSteady:
            return "A steady run at a confident, moderate effort — powered by mid- to high-energy songs that help you lock into a groove and hold it."
        case .shortWaves:
            return "A playful fartlek: one song easy, one song high-energy — repeat until you’re done. Let the music set the pace changes."
        case .longWaves:
            return "A longer fartlek: two songs easy, two songs high-energy — repeated for a balanced mix of cruising and pushing."
        case .pyramid:
            return "Start easy and gradually build up to your hardest effort in the middle, then step back down to finish relaxed. The playlist’s energy rises and falls to guide you."
        case .kicker:
            return "A steady run with a surprise ending — the last few tracks are all high-energy to push you into a strong, satisfying finish."
        }
    }

    // Map a template to a background asset name located under Assets `templateimages`.
    private func templateBackgroundAssetName(for template: RunTemplateType?) -> String {
        guard let t = template else { return "light" }
        switch t {
        case .easyRun: return "light"
        case .strongSteady: return "tempo"
        case .shortWaves: return "hiit"
        case .longWaves: return "intervals"
        case .pyramid: return "pyramid"
        case .kicker: return "kicker"
        }
    }
}

// Token chip for displaying selected filters in Home sync'd playlist section
private struct FilterTokenChip: View {
    let title: String
    var body: some View {
        Text(title)
            .font(RCFont.regular(13))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(Color.white.opacity(0.15))
            .cornerRadius(4)
    }
}
private struct RecommendationCard: View {
    let title: String
    let template: RunTemplateType
    let minutes: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(template.rawValue)
                .font(.title3).bold()
            Text("\(minutes) min")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.12))
        .cornerRadius(12)
    }
}

private struct CustomizeStubView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Customization coming soon")
                Button("Close") { dismiss() }
            }
            .padding()
            .navigationTitle("Customize Run")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


