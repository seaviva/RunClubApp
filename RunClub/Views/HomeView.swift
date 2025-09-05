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
    @AppStorage("runsPerWeek") private var runsPerWeek: Int = 3
    @AppStorage("preferredDurationCategory") private var preferredDurationRaw: String = DurationCategory.medium.rawValue
    @State private var showingCustomize = false
    @State private var customTemplate: RunTemplateType?
    @State private var customDuration: DurationCategory?
    @State private var customGenres: Set<Genre> = []
    @State private var customDecades: Set<Decade> = []
    @State private var customPrompt: String = ""
    @State private var showingSettings = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedDate: Date = Date()
    @State private var showingMonth = false
    @State private var isGenerating = false
    // Per-day state: generated playlist URL and completion flag (in-memory for now)
    @State private var generatedURLByDay: [String: URL] = [:]
    @State private var completedDays: Set<String> = []
    private let schedule = ScheduleService()
    private let spotify = SpotifyService()

    private var preferences: UserPreferences {
        let duration = DurationCategory(rawValue: preferredDurationRaw) ?? .medium
        return UserPreferences(runsPerWeek: runsPerWeek, preferredDuration: duration)
    }

    var body: some View {
        let rec = schedule.recommendationForToday(preferences: preferences, date: selectedDate)
        let dayKey = dayKeyString(for: selectedDate)
        let generatedURL = generatedURLByDay[dayKey]
        let isDone = completedDays.contains(dayKey)
        VStack(spacing: 0) {
            // Top calendar header area
            VStack(spacing: 12) {
                HStack(spacing :8) {
                    // THIS WEEK summary
                    Text("THIS WEEK")
                            .font(RCFont.medium(15))
                    HStack(spacing: 4) {
                        Text("\(completedCountInWeek(for: selectedDate))")
                            .font(RCFont.medium(15))
                            .foregroundColor(Color(red: 0.0, green: 1.0, blue: 0.4667))
                        Text("/")
                            .font(RCFont.medium(15))
                            .foregroundColor(Color.white.opacity(0.25))
                        Text("\(runsPerWeek)")
                            .font(RCFont.medium(15))
                    }
                    Spacer()
                    HStack(spacing: 24) {
                        if auth.isAuthorized {
                            Button { showingMonth = true } label: {
                                Image(systemName: "calendar")
                                    .imageScale(.large)
                                    .foregroundColor(.white)
                            }
                        }
                        Button { showingSettings = true } label: {
                            Image(systemName: "ellipsis")
                                .imageScale(.large)
                                .foregroundColor(.white)
                                
                        }
                    }

                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12) 

                if auth.isAuthorized {
                    WeekStrip(selectedDate: $selectedDate, preferences: preferences, schedule: schedule, isCompleted: { date in
                        completedDays.contains(dayKeyString(for: date))
                    })
                        //.padding(.horizontal, 8)
                        .padding(.bottom, 12)
                }
            }
            .background(
                LinearGradient(colors: [Color(red: 0.0118, green: 0.0118, blue: 0.0118), Color(red: 0.0627, green: 0.0627, blue: 0.0627)],
                               startPoint: .top,
                               endPoint: .bottom)
            )
            .overlay(Rectangle().fill(Color.white.opacity(0.03)).frame(height: 1), alignment: .bottom)
            .padding(.bottom, 8)

            // Content area
            if auth.isAuthorized {
                VStack(alignment: .leading, spacing: 24) {
                    // Day header with completion check
                    HStack(spacing: 10) {
                        Text(Calendar.current.isDateInToday(selectedDate) ? "TODAY" : formattedDate(selectedDate).uppercased())
                            .font(RCFont.medium(32))
                        Spacer()
                        if isDone {
                            ZStack {
                                Rectangle()
                                    .fill(Color(red: 0.0, green: 1.0, blue: 0.4667).opacity(0.25))
                                    .frame(width: 28, height: 28)
                                    .cornerRadius(2)

                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(red: 0.0, green: 1.0, blue: 0.4667))
                                    .font(.system(size: 16, weight: .medium))
                            }

                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .overlay(Rectangle().fill(Color.white).frame(height: 1).padding(.horizontal, 20), alignment: .bottom)
                    .padding(.bottom, 8)
                    

                    // Compute bin color and active template for this day
                    let scheduledTemplate: RunTemplateType? = rec.template
                    // Active template prioritizes custom selection; on rest days, it's nil until the user customizes
                    let activeTemplate: RunTemplateType? = customTemplate ?? (rec.isRunDay ? scheduledTemplate : nil)
                    let isRunDay: Bool = rec.isRunDay || (activeTemplate != nil)
                    let binColor: Color = {
                        guard let t = activeTemplate else { return Color.white.opacity(0.4) }
                        switch t {
                        case .easyRun, .longEasy: return Color(red: 0.0, green: 0.81, blue: 1.0) // #00CFFF
                        case .strongSteady, .pyramid, .kicker: return Color(red: 1.0, green: 0.70, blue: 0.0) // #FFB300
                        case .shortWaves, .longWaves: return Color(red: 1.0, green: 0.20, blue: 0.40) // #FF3366
                        }
                    }()
                    let headerColor: Color = isDone ? Color(red: 0.0, green: 1.0, blue: 0.4667) : (isRunDay ? binColor : Color.white.opacity(0.4))

                    // Recommended workout section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Rectangle().fill(headerColor).frame(width: 8, height: 8)
                            Text(activeTemplate == nil ? "RECOMMENDED WORKOUT" : "CUSTOM RUN")
                                .font(RCFont.regular(13))
                                .foregroundColor(headerColor)
                        }
                        Text((activeTemplate?.rawValue ?? "REST").uppercased())
                            .font(RCFont.semiBold(20))
                            .foregroundColor(.white)
                        Text(activeTemplate == nil ? "Take it easy, do some stretching, or lift some weights." : runDescription(for: activeTemplate!))
                            .font(RCFont.regular(15))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    // Sync'd playlist selection
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Rectangle().fill(headerColor).frame(width: 8, height: 8)
                            Text("SYNC’D PLAYLIST")
                                .font(RCFont.regular(13))
                                .foregroundColor(headerColor)
                        }
                        let hasFilters = !customGenres.isEmpty || !customDecades.isEmpty
                        if !isRunDay {
                            Text("NONE")
                                .font(RCFont.semiBold(20))
                            Text("Select a workout in the customize sheet to generate a playlist.")
                                .font(RCFont.regular(15))
                                .foregroundColor(.white.opacity(0.6))
                        } else {
                            Text(hasFilters ? "CUSTOM" : "AUTO")
                                .font(RCFont.semiBold(20))
                            Text("Various picks from your likes and similar recommended songs")
                                .font(RCFont.regular(15))
                                .foregroundColor(.white.opacity(0.6))
                            if hasFilters {
                                let tokens = customGenres.map { $0.displayName } + customDecades.map { $0.displayName }
                                FlowLayout(spacing: 6, runSpacing: 6) {
                                    ForEach(tokens, id: \.self) { token in
                                        FilterTokenChip(title: token)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    if isGenerating {
                        HStack(spacing: 8) {
                            ProgressView(); Text("Generating…").foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 20)
                    }
                }
            } else {
                Button("Connect Spotify") { auth.startLogin() }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
            if auth.isAuthorized {
                HStack(spacing: 16) {
                    if generatedURL == nil {
                        // Pre-generation: Customize (secondary) + Create (primary)
                        Button("Customize") { showingCustomize = true }
                            .buttonStyle(SecondaryOutlineButtonStyle())
                        Button("Create Playlist") {
                            generate()
                        }
                        .buttonStyle(PrimaryFilledButtonStyle())
                        .disabled(isGenerating || (!rec.isRunDay && customTemplate == nil))
                    } else if !completedDays.contains(dayKey) {
                        // Post-generation: Open in Spotify (tertiary) + Run Complete (primary green)
                        Button("Open Playlist") { openURL(generatedURL!) }
                            .buttonStyle(SecondaryOutlineButtonStyle())
                        Button("Run Complete") { markDone(dayKey) }
                            .buttonStyle(PrimaryFilledColorButtonStyle(color: Color(red: 0.0, green: 1.0, blue: 0.4667)))
                    } else {
                        // Post-complete: Reset Completion (tertiary)
                        Button("Reset Completion") { resetDay(dayKey) }
                            .buttonStyle(SecondaryOutlineButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: $showingCustomize) {
            let currentRec = schedule.recommendationForToday(preferences: preferences)
            let initialTemplate = currentRec.template ?? .easyRun
            let initialDuration = currentRec.suggestedDurationCategory ?? preferences.preferredDuration
            CustomizeRunView(
                initialTemplate: initialTemplate,
                initialDuration: initialDuration,
                initialGenres: customGenres,
                initialDecades: customDecades,
                initialPrompt: customPrompt
            ) { t, d, genres, decades, prompt in
                customTemplate = t
                customDuration = d
                customGenres = genres
                customDecades = decades
                customPrompt = prompt
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView().environmentObject(auth).environmentObject(crawlCoordinator) }
        .sheet(isPresented: $showingMonth) {
            MonthCalendarSheet(selectedDate: $selectedDate, calendar: .current) { date in
                schedule.recommendationForToday(preferences: preferences, date: date).isRunDay
            }
            .presentationDetents([.medium, .large])
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
            guard let token = await auth.accessToken() else { return }
            spotify.accessTokenProvider = { token }
            do {
                let rec = schedule.recommendationForToday(preferences: preferences, date: selectedDate)
                let template = customTemplate ?? rec.template ?? .easyRun
                let duration = customDuration ?? rec.suggestedDurationCategory ?? preferences.preferredDuration
                var name = "RunClub · \(template.rawValue) · \(duration.displayName) · \(Date().formatted(date: .numeric, time: .omitted))"
                // Prefer local generator using SwiftData cache
                let local = LocalGenerator(modelContext: modelContext)
                let url = try await local.generatePlaylist(name: name,
                                                           template: template,
                                                           durationCategory: duration,
                                                           genres: Array(customGenres),
                                                           decades: Array(customDecades),
                                                           spotify: spotify)
                generatedURLByDay[dayKeyString(for: selectedDate)] = url
                await UIApplication.shared.open(url)
            } catch {
                // Surface generator error and fallback to simple likes playlist
                let message = (error as NSError).localizedDescription
                print("Generator error:", message)
                errorMessage = message
                showError = true
                do {
                    // Fallback: legacy remote generator
                    let rec = schedule.recommendationForToday(preferences: preferences, date: selectedDate)
                    let template = customTemplate ?? rec.template ?? .easyRun
                    let duration = customDuration ?? rec.suggestedDurationCategory ?? preferences.preferredDuration
                    let name = "RunClub · \(template.rawValue) · \(duration.displayName) · \(Date().formatted(date: .numeric, time: .omitted))"
                    let url = try await spotify.generateSimpleRunPlaylist(
                        name: name,
                        template: template,
                        durationCategory: duration,
                        genres: Array(customGenres),
                        decades: Array(customDecades)
                    )
                    generatedURLByDay[dayKeyString(for: selectedDate)] = url
                    await UIApplication.shared.open(url)
                } catch {
                    // Final fallback: likes-only
                    do {
                        let fallbackName = "RunClub · Test \(Date().formatted(date: .numeric, time: .omitted))"
                        let url = try await spotify.createSimplePlaylistFromLikes(name: fallbackName)
                        generatedURLByDay[dayKeyString(for: selectedDate)] = url
                        await UIApplication.shared.open(url)
                    } catch {
                        errorMessage = (error as NSError).localizedDescription
                        showError = true
                    }
                }
            }
        }
    }

    private func markDone(_ key: String) { completedDays.insert(key) }
    private func resetDay(_ key: String) { completedDays.remove(key); generatedURLByDay.removeValue(forKey: key) }
    private func openURL(_ url: URL) { Task { await UIApplication.shared.open(url) } }
    private func dayKeyString(for date: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; return f.string(from: date) }

    private func completedCountInWeek(for date: Date) -> Int {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        let dates = completedDays.compactMap { f.date(from: $0) }
        return dates.filter { cal.isDate($0, equalTo: date, toGranularity: .weekOfYear) && cal.isDate($0, equalTo: date, toGranularity: .yearForWeekOfYear) }.count
    }

    private func formattedDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE, MMM d"
        return df.string(from: date)
    }

    private func selectionSummary() -> String {
        let hasTemplate = (customTemplate != nil)
        let hasDuration = (customDuration != nil)
        let hasGenres = !customGenres.isEmpty
        let hasDecades = !customDecades.isEmpty
        let hasPrompt = !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !(hasTemplate || hasDuration || hasGenres || hasDecades || hasPrompt) {
            return "Auto"
        }
        var parts: [String] = []
        if let t = customTemplate { parts.append(t.rawValue) }
        if let d = customDuration { parts.append(d.displayName) }
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
        case .longEasy:
            return "An extended, relaxed run with smooth, low- to mid-energy tracks to help you settle in and keep the pace light for the long haul."
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
    let category: DurationCategory
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(template.rawValue)
                .font(.title3).bold()
            Text(category.displayName)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.12))
        .cornerRadius(12)
    }
}

private struct RestCard: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text("Rest")
                .font(.title3).bold()
            Text("You can still create a custom run below.")
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


