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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("runsPerWeek") private var runsPerWeek: Int = 3
    @AppStorage("preferredDurationCategory") private var preferredDurationRaw: String = DurationCategory.medium.rawValue
    @State private var customTemplate: RunTemplateType?
    @State private var customDuration: DurationCategory?
    @State private var customGenres: Set<Genre> = []
    @State private var customDecades: Set<Decade> = []
    @State private var customPrompt: String = ""
    @State private var customMinutes: Int? = nil
    // Carousel selection for templates on Home
    @State private var selectedTemplateCarousel: RunTemplateType? = nil
    // New sheets for filters and duration
    @State private var showingFiltersSheet = false
    @State private var showingDurationSheet = false
    @State private var showingSettings = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedDate: Date = Date()
    @State private var showingMonth = false
    @State private var isGenerating = false
    // Per-day state: generated playlist URL and completion flag (in-memory for now)
    @State private var generatedURLByDay: [String: URL] = [:]
    @State private var completedDays: Set<String> = []
    @State private var currentUserId: String? = nil
    @State private var showingStartRun = false
    @State private var showingPreview = false
    @State private var lastGeneratedTemplate: RunTemplateType? = nil
    @State private var lastGeneratedDuration: DurationCategory? = nil
    @State private var pendingTemplate: RunTemplateType? = nil
    @State private var pendingDuration: DurationCategory? = nil
    private let schedule = ScheduleService()
    private let spotify = SpotifyService()

    // Order templates for the Home carousel. Rest is last unless it's the recommended item.
    private func templateCarouselOrder(recommended: RunTemplateType?) -> [RunTemplateType] {
        var base = RunTemplateType.allCases.filter { $0 != .rest }
        base.append(.rest)
        guard let rec = recommended else { return base }
        if rec == .rest { return [.rest] + base.filter { $0 != .rest } }
        return [rec] + base.filter { $0 != rec }
    }

    private var preferences: UserPreferences {
        let duration = DurationCategory(rawValue: preferredDurationRaw) ?? .medium
        return UserPreferences(runsPerWeek: runsPerWeek, preferredDuration: duration)
    }

    var body: some View {
        let rec = schedule.recommendationForToday(preferences: preferences, date: selectedDate)
        let dayKey = dayKeyString(for: selectedDate)
        let generatedURL = generatedURLByDay[dayKey]
        let isDone = completedDays.contains(dayKey)
        let scheduledTemplate: RunTemplateType? = rec.template
        let defaultTemplate: RunTemplateType? = rec.isRunDay ? scheduledTemplate : .rest
        let isToday = Calendar.current.isDateInToday(selectedDate)
        let isPast = Calendar.current.startOfDay(for: selectedDate) < Calendar.current.startOfDay(for: Date())
        let isFuture = !isToday && !isPast
        let activeTemplate: RunTemplateType? = isFuture ? defaultTemplate : (selectedTemplateCarousel ?? customTemplate ?? defaultTemplate)
        let activeDuration: DurationCategory = customDuration ?? rec.suggestedDurationCategory ?? preferences.preferredDuration
        let isRunDay: Bool = rec.isRunDay || (activeTemplate != nil)
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
                // Header: centered HStack with left logo, middle date, right calendar
                HStack(spacing: 0) {
                    Button { showingSettings = true } label: {
                        Image("runclublogo")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                    .frame(width: 44, height: 44, alignment: .center)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)

                    Spacer(minLength: 8)

                    Text(Calendar.current.isDateInToday(selectedDate) ? "TODAY" : formattedDate(selectedDate).uppercased())
                        .font(RCFont.light(14))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)

                    Spacer(minLength: 8)

                    if auth.isAuthorized {
                        Button { showingMonth = true } label: {
                            Image("calendarblank")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.white)
                        }
                        .frame(width: 44, height: 44, alignment: .center)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                    } else {
                        // keep alignment consistent when unauthorized
                        Color.clear.frame(width: 48, height: 48)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .frame(height: 44, alignment: .center)

                // Main content fills remaining space; bottom-centered
                if auth.isAuthorized {
                VStack(spacing: 20) {
                    // When completed: show static name + description (no carousel)
                    if isDone, let t = activeTemplate ?? defaultTemplate {
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
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 32)
                    } else if isFuture, let t = defaultTemplate {
                        // Future day: show only the recommended card, no carousel
                        VStack(spacing: 12) {
                            Text("RECOMMENDED")
                                .font(RCFont.light(14))
                                .foregroundColor(Color(hex: 0xFFCC33))
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
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 32)
                    } else if let initial = activeTemplate ?? defaultTemplate {
                        // Carousel of templates/rest (only when not completed)
                        let selection = Binding<RunTemplateType>(
                            get: { selectedTemplateCarousel ?? initial },
                            set: { newVal in selectedTemplateCarousel = newVal; customTemplate = newVal }
                        )
                        TabView(selection: selection) {
                            ForEach(templateCarouselOrder(recommended: defaultTemplate)) { t in
                                VStack(spacing: 12) {
                                    if let recT = defaultTemplate, recT == t {
                                        Text(isToday ? "RECOMMENDED TODAY" : "RECOMMENDED")
                                            .font(RCFont.light(14))
                                            .foregroundColor(Color(hex: 0xFFCC33))
                                    }
                                    Text(t.rawValue)
                                        .font(RCFont.powerGroteskLight(60))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .padding(.horizontal, 20)
                                    let desc: String = {
                                        let isPast = Calendar.current.startOfDay(for: selectedDate) < Calendar.current.startOfDay(for: Date())
                                        let done = completedDays.contains(dayKey)
                                        if isPast && !done { return "No run recorded" }
                                        return runDescription(for: t)
                                    }()
                                    Text(desc)
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
                        .onChange(of: selectedTemplateCarousel) { _, _ in }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 16)
                } else {
                    Button("Connect Spotify") { auth.startLogin() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 32)
                }

                // Bottom controls: buttons bar + CTA, pinned to bottom
                VStack(spacing: 0) {
                    // Buttons bar (filters + duration)
                    if auth.isAuthorized && (isRunDay || (!isToday && !isPast)) {
                        if isDone {
                            HStack(spacing: 16) {
                                Spacer()
                                Button(action: {}) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "music.note.list").font(.system(size: 16, weight: .regular))
                                        Text("NA")
                                            .font(RCFont.medium(15))
                                    }
                                    .foregroundColor(Color(hex: 0x1FCBFF))
                                    .padding(.horizontal, 20)
                                    .frame(height: 48)
                                    .background(Color(hex: 0x33B1FF, alpha: 0.25))
                                    .cornerRadius(28)
                                }
                                .disabled(true)
                                Button(action: {}) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "timer").font(.system(size: 16, weight: .regular))
                                        Text("NA").font(RCFont.medium(15))
                                    }
                                    .foregroundColor(Color(hex: 0xFF3333))
                                    .padding(.horizontal, 20)
                                    .frame(height: 48)
                                    .background(Color(hex: 0xFF3333, alpha: 0.25))
                                    .cornerRadius(28)
                                }
                                .disabled(true)
                                Spacer()
                            }
                            .frame(height: 68)
                        } else if isToday {
                            HStack(spacing: 16) {
                                Spacer()
                                let isRest = (selectedTemplateCarousel ?? activeTemplate) == .rest
                                let filtersApplied = !customGenres.isEmpty || !customDecades.isEmpty
                                Button(action: { showingFiltersSheet = true }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "music.note.list").font(.system(size: 16, weight: .regular))
                                        Text(isRest ? "NA" : (filtersApplied ? "CUSTOM" : "AUTO"))
                                            .font(RCFont.medium(15))
                                    }
                                    .foregroundColor(Color(hex: 0x1FCBFF))
                                    .padding(.horizontal, 20)
                                    .frame(height: 48)
                                    .background(Color(hex: 0x33B1FF, alpha: 0.25))
                                    .cornerRadius(28)
                                }
                                .disabled(isRest)
                                Button(action: { showingDurationSheet = true }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "timer").font(.system(size: 16, weight: .regular))
                                        let label = customMinutes != nil ? "~\(customMinutes!)min" : "~\(activeDuration.midpointMinutes)min"
                                        Text(isRest ? "NA" : label).font(RCFont.medium(15))
                                    }
                                    .foregroundColor(Color(hex: 0xFF3333))
                                    .padding(.horizontal, 20)
                                    .frame(height: 48)
                                    .background(Color(hex: 0xFF3333, alpha: 0.25))
                                    .cornerRadius(28)
                                }
                                .disabled(isRest)
                                Spacer()
                            }
                            .frame(height: 68)
                        } else {
                            // Future day: show disabled buttons to keep layout consistent
                            HStack(spacing: 16) {
                                Spacer()
                                Button(action: {}) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "music.note.list").font(.system(size: 16, weight: .regular))
                                        Text("NA")
                                            .font(RCFont.medium(15))
                                    }
                                    .foregroundColor(Color(hex: 0x1FCBFF))
                                    .padding(.horizontal, 20)
                                    .frame(height: 48)
                                    .background(Color(hex: 0x33B1FF, alpha: 0.25))
                                    .cornerRadius(28)
                                }
                                .disabled(true)
                                Button(action: {}) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "timer").font(.system(size: 16, weight: .regular))
                                        Text("NA").font(RCFont.medium(15))
                                    }
                                    .foregroundColor(Color(hex: 0xFF3333))
                                    .padding(.horizontal, 20)
                                    .frame(height: 48)
                                    .background(Color(hex: 0xFF3333, alpha: 0.25))
                                    .cornerRadius(28)
                                }
                                .disabled(true)
                                Spacer()
                            }
                            .frame(height: 68)
                        }
                    }

                    // CTA row
                    
                    if auth.isAuthorized {
                        HStack(spacing: 16) {
                            if isToday {
                                if completedDays.contains(dayKey) {
                                    Button("RESET RUN") { resetDay(dayKey) }
                                        .buttonStyle(PrimaryFilledButtonStyle())
                                } else if isRunDay {
                                    Spacer()
                                    Button(action: {
                                        if let _ = generatedURLByDay[dayKey] {
                                            showingStartRun = true
                                        } else {
                                            let rec = schedule.recommendationForToday(preferences: preferences, date: selectedDate)
                                            let template = selectedTemplateCarousel ?? customTemplate ?? rec.template ?? .easyRun
                                            let duration = customDuration ?? rec.suggestedDurationCategory ?? preferences.preferredDuration
                                            pendingTemplate = template
                                            pendingDuration = duration
                                            showingPreview = true
                                        }
                                    }) {
                                        Text("LET’S RUN")
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                    }
                                    .buttonStyle(SecondaryOutlineButtonStyle())
                                    .disabled((selectedTemplateCarousel ?? activeTemplate) == .rest || isGenerating)
                                    Spacer(minLength: 0)
                                } else {
                                    Spacer()
                                    // Past/future non-run states keep layout centered
                                    Spacer()
                                }
                            } else if isPast {
                                Spacer()
                                if completedDays.contains(dayKey) {
                                    Button(action: { resetDay(dayKey) }) { Text("RESET RUN").lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                                        .buttonStyle(GhostWhiteButtonStyle())
                                }
                                Button(action: { selectedDate = Date() }) { Text("GO TO TODAY").lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                                    .buttonStyle(SecondaryOutlineButtonStyle())
                                Spacer()
                            } else {
                                Spacer()
                                Button(action: { selectedDate = Date() }) { Text("GO TO TODAY").lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                                    .buttonStyle(SecondaryOutlineButtonStyle())
                                Spacer()
                            }
                        }
                        .padding(.top, 8)
                    } else { EmptyView() }
                    Spacer()
                }
                .frame(height: 206 + max(0, proxy.safeAreaInsets.bottom))
                .padding(.horizontal, 20)
            }
            .onChange(of: selectedDate) { _, _ in
                // Clear custom selections when changing day
                customTemplate = nil
                customDuration = nil
                customGenres = []
                customDecades = []
                customPrompt = ""
            }
            .onAppear {
                Task {
                    if let token = await auth.accessToken() {
                        spotify.accessTokenProvider = { token }
                        if let uid = try? await spotify.currentUserId() {
                            currentUserId = uid
                            loadCompletedDaysFromStore(userId: uid)
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
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingDurationSheet) {
            DurationPickerSheet(initialMinutes: customMinutes, category: activeDuration) { minutes in
                customMinutes = minutes
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSettings) { SettingsView().environmentObject(auth).environmentObject(crawlCoordinator) }
        .sheet(isPresented: $showingMonth) {
            MonthCalendarSheet(
                selectedDate: $selectedDate,
                calendar: .current,
                isRunDay: { date in
                    schedule.recommendationForToday(preferences: preferences, date: date).isRunDay
                },
                isCompleted: { date in
                    completedDays.contains(dayKeyString(for: date))
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingPreview) {
            // Fallback to today's recommendation if pending values are nil
            let rec = schedule.recommendationForToday(preferences: preferences, date: selectedDate)
            let t = pendingTemplate ?? rec.template ?? .easyRun
            let d = pendingDuration ?? rec.suggestedDurationCategory ?? preferences.preferredDuration
            RunPreviewSheet(template: t, duration: d, customMinutes: customMinutes, genres: Array(customGenres), decades: Array(customDecades)) { preview in
                Task { await confirm(preview: preview) }
            }
            .presentationDetents([.large])
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showingStartRun) {
            if let url = generatedURLByDay[dayKeyString(for: selectedDate)],
               let t = lastGeneratedTemplate,
               let d = lastGeneratedDuration {
                StartRunView(playlistURI: url.absoluteString, template: t, duration: d) {
                    // Mark the run complete for the selected day and refresh UI
                    let key = dayKeyString(for: selectedDate)
                    markDone(key)
                }
                    .presentationDetents([.large])
                    .interactiveDismissDisabled(true)
                    .presentationDragIndicator(.hidden)
            } else {
                Text("No run available")
            }
        }
        // Always snap to today when app becomes active or the day changes
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { selectedDate = Date() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            selectedDate = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            selectedDate = Date()
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
            let rec = schedule.recommendationForToday(preferences: preferences, date: selectedDate)
            let template = customTemplate ?? rec.template ?? .easyRun
            let duration = customDuration ?? rec.suggestedDurationCategory ?? preferences.preferredDuration
            pendingTemplate = template
            pendingDuration = duration
            showingPreview = true
        }
    }

    private func confirm(preview: PreviewRun) async {
            guard let token = await auth.accessToken() else { return }
            spotify.accessTokenProvider = { token }
            do {
            let url = try await spotify.createConfirmedPlaylist(from: preview)
            let key = dayKeyString(for: selectedDate)
            generatedURLByDay[key] = url
            lastGeneratedTemplate = preview.template
            lastGeneratedDuration = preview.duration
            // Clear custom minutes after successful confirmation so it only applies to this run
            customMinutes = nil
            showingPreview = false
            showingStartRun = true
            } catch {
            errorMessage = (error as NSError).localizedDescription
            showError = true
        }
    }

    private func markDone(_ key: String) {
        completedDays.insert(key)
        persistCompleted(dateKey: key)
    }
    private func resetDay(_ key: String) {
        completedDays.remove(key)
        generatedURLByDay.removeValue(forKey: key)
        deleteCompleted(dateKey: key)
    }
    private func loadCompletedDaysFromStore(userId: String) {
        do {
            let descriptor = FetchDescriptor<CompletedRun>(predicate: #Predicate { $0.userId == userId })
            let runs = try modelContext.fetch(descriptor)
            completedDays = Set(runs.map { $0.dateKey })
        } catch {
            // no-op
        }
    }
    private func persistCompleted(dateKey: String) {
        guard let uid = currentUserId else { return }
        let existing = try? modelContext.fetch(FetchDescriptor<CompletedRun>(predicate: #Predicate { $0.userId == uid && $0.dateKey == dateKey }))
        if let existing, !existing.isEmpty { return }
        let record = CompletedRun(userId: uid, dateKey: dateKey)
        modelContext.insert(record)
        try? modelContext.save()
    }
    private func deleteCompleted(dateKey: String) {
        guard let uid = currentUserId else { return }
        if let matches = try? modelContext.fetch(FetchDescriptor<CompletedRun>(predicate: #Predicate { $0.userId == uid && $0.dateKey == dateKey })) {
            for m in matches { modelContext.delete(m) }
            try? modelContext.save()
        }
    }
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
        case .rest:
            return "A day to focus on other stuff - do some yoga, strength exercises, a long walk with your furry friend, or just take a really nice long nap."
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

    // Map a template to a background asset name located under Assets `templateimages`.
    private func templateBackgroundAssetName(for template: RunTemplateType?) -> String {
        guard let t = template else { return "rest" }
        switch t {
        case .rest: return "rest"
        case .easyRun: return "light"
        case .strongSteady: return "tempo"
        case .longEasy: return "longeasy"
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
            Text("A day to focus on other stuff - do some yoga, strength exercises, or just take a really nice long nap.")
                .font(RCFont.regular(16))
                .foregroundColor(.secondary)
                .lineSpacing(8)
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


