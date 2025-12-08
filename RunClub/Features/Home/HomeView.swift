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
    
    // Run setup state (passed from RunSetupSheet to RunPreviewSheet)
    @State private var pendingTemplate: RunTemplateType = .light
    @State private var pendingMinutes: Int = 30
    @State private var pendingGenres: Set<Genre> = []
    @State private var pendingDecades: Set<Decade> = []
    
    // Sheet states
    @State private var showingRunFlow = false
    @State private var showingSettings = false
    @State private var showingLog = false
    @State private var showingStartRun = false
    
    // Error handling
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isGenerating = false
    
    // Current-session generated playlist URL
    @State private var generatedURL: URL? = nil
    @State private var currentUserId: String? = nil
    @State private var lastGeneratedTemplate: RunTemplateType? = nil
    @State private var lastRunMinutes: Int? = nil
    
    private let spotify = SpotifyService()

    var body: some View {
        ZStack {
            // Static background image - fills entire screen
            Image("homestreet")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea(.all)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                // Header: logo on left, log + settings on right
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
                .padding(.horizontal, 28)
                .frame(height: 44, alignment: .center)

                // Main CTA area
                if AuthService.overrideToken() != nil {
                    Spacer()
                    
                    // Main headline text
                    Text("It's a great\nday for a run")
                        .font(RCFont.powerGroteskLight(60))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(0)
                        .padding(.horizontal, 20)
                    
                    // Weather card
                    WeatherCardView()
                        .padding(.horizontal, 48)
                        .padding(.top, 32)
                    
                    Spacer()
                    
                    // Single CTA button
                    Button(action: {
                        if generatedURL != nil {
                            showingStartRun = true
                        } else {
                            showingRunFlow = true
                        }
                    }) {
                        Text(generatedURL != nil ? "CONTINUE RUN" : "LET'S GO")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(SecondaryOutlineButtonStyle())
                    .disabled(isGenerating)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 16)
                } else {
                    Spacer()
                    // Connect Spotify prompt
                    Button("Connect Spotify") { showingSettings = true }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 80)
                }
            }
            .safeAreaPadding(.top)
            .onAppear {
                // Initialize pending minutes from defaults
                pendingMinutes = defaultRunMinutes
                
                // Load default filters
                let defaultGenres = DefaultFiltersHelper.getDefaultGenres()
                let defaultDecades = DefaultFiltersHelper.getDefaultDecades()
                if !defaultGenres.isEmpty {
                    pendingGenres = defaultGenres
                }
                if !defaultDecades.isEmpty {
                    pendingDecades = defaultDecades
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
        // Sheets
        .sheet(isPresented: $showingRunFlow) {
            RunFlowSheet(
                initialTemplate: pendingTemplate,
                initialMinutes: pendingMinutes,
                initialGenres: pendingGenres,
                initialDecades: pendingDecades
            ) { preview in
                // Update pending values from the confirmed preview
                pendingTemplate = preview.template
                pendingMinutes = preview.runMinutes
                Task { await confirm(preview: preview) }
            }
            .presentationDetents([.large])
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(auth)
                .environmentObject(crawlCoordinator)
                .environmentObject(progressStore)
                .environmentObject(playlistsCoordinator)
                .environmentObject(playlistsProgress)
        }
        .sheet(isPresented: $showingLog) {
            RunLogView().environment(\.modelContext, modelContext)
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

    private func confirm(preview: PreviewRun) async {
        // Use override-first provider to support StatsForSpotify login fully
        spotify.accessTokenProvider = { AuthService.overrideToken() ?? (AuthService.sharedTokenSync() ?? "") }
        do {
            let url = try await spotify.createConfirmedPlaylist(from: preview)
            generatedURL = url
            lastGeneratedTemplate = preview.template
            lastRunMinutes = preview.runMinutes
            showingRunFlow = false
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
}

// MARK: - Weather Card View
struct WeatherCardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: Date and temperature
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wednesday, 26th")
                        .font(RCFont.medium(16))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 6) {
                        Text("☀️")
                            .font(.system(size: 14))
                        Text("Sunny")
                            .font(RCFont.regular(14))
                            .foregroundColor(Color(hex: 0xFFD60A))
                    }
                }
                
                Spacer()
                
                Text("68°")
                    .font(RCFont.light(48))
                    .foregroundColor(.white)
            }
            
            // Bottom row: Weather details
            HStack(spacing: 0) {
                // UV / AQI column
                VStack(alignment: .leading, spacing: 4) {
                    Text("UV  5:45am")
                        .font(RCFont.regular(12))
                        .foregroundColor(.white.opacity(0.7))
                    Text("AQI  6:31pm")
                        .font(RCFont.regular(12))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Sunrise/Sunset column
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "sunrise.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                        Text("5:45am")
                            .font(RCFont.regular(12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "sunset.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                        Text("6:31pm")
                            .font(RCFont.regular(12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Spacer()
                
                // High/Low temps
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 2) {
                        Text("L")
                            .font(RCFont.regular(12))
                            .foregroundColor(Color(hex: 0x4A90D9))
                        Text("68")
                            .font(RCFont.regular(12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    HStack(spacing: 2) {
                        Text("H")
                            .font(RCFont.regular(12))
                            .foregroundColor(Color(hex: 0xE55C3A))
                        Text("48")
                            .font(RCFont.regular(12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}
