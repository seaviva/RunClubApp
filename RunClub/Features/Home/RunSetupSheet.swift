//
//  RunSetupSheet.swift
//  RunClub
//

import SwiftUI

struct RunSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTemplate: RunTemplateType = .light
    @State private var selectedMinutes: Int
    @State private var selectedGenres: Set<Genre> = []
    @State private var selectedDecades: Set<Decade> = []
    
    let onCreateWorkout: (RunTemplateType, Int, Set<Genre>, Set<Decade>) -> Void
    
    init(
        initialTemplate: RunTemplateType = .light,
        initialMinutes: Int? = nil,
        initialGenres: Set<Genre> = [],
        initialDecades: Set<Decade> = [],
        onCreateWorkout: @escaping (RunTemplateType, Int, Set<Genre>, Set<Decade>) -> Void
    ) {
        _selectedTemplate = State(initialValue: initialTemplate)
        _selectedGenres = State(initialValue: initialGenres)
        _selectedDecades = State(initialValue: initialDecades)
        self.onCreateWorkout = onCreateWorkout
        
        // Use provided initialMinutes, or read from UserDefaults, or fallback to 30
        let defaultMinutes = UserDefaults.standard.integer(forKey: "defaultRunMinutes")
        let effectiveDefault = defaultMinutes > 0 ? defaultMinutes : 30
        _selectedMinutes = State(initialValue: initialMinutes ?? effectiveDefault)
    }
    
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
                        // Title row (scrolls with content)
                        titleRow
                        
                        // Three subsections
                        VStack(alignment: .leading, spacing: 20) {
                            // Workout Type Section
                            workoutTypeSection
                            
                            // Duration Section
                            durationSection
                            
                            // Filter Section
                            filterSection
                        }
                        .padding(.top, 12)
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 160) // Space for CTA
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
                    Button(action: createWorkout) {
                        Text("NEXT")
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
                .padding(.bottom, 34) // Safe area approximate
                .background(Color.black)
            }
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            // Apply default filters if none provided
            let defaultGenres = DefaultFiltersHelper.getDefaultGenres()
            let defaultDecades = DefaultFiltersHelper.getDefaultDecades()
            if selectedGenres.isEmpty && !defaultGenres.isEmpty {
                selectedGenres = defaultGenres
            }
            if selectedDecades.isEmpty && !defaultDecades.isEmpty {
                selectedDecades = defaultDecades
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        // Top row with help button, step indicator, close button
        ZStack {
            // Step indicator (two bars)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 34, height: 2)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 34, height: 2)
            }
            
            HStack {
                Button(action: { /* Help action */ }) {
                    Image("Question")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
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
    
    // MARK: - Title Row (scrolls with content)
    
    private var titleRow: some View {
        HStack {
            Text("Run Setup")
                .font(RCFont.medium(28))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Workout Type Section
    
    private var workoutTypeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image("SneakerMove")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundColor(.white)
                Text("Select Workout Type")
                    .font(RCFont.medium(16))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 18)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(RunTemplateType.allCases) { template in
                        WorkoutTemplateCard(
                            template: template,
                            isSelected: selectedTemplate == template,
                            onTap: { selectedTemplate = template }
                        )
                    }
                }
                .padding(.horizontal, 18)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Duration Section
    
    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image("Timer")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundColor(.white)
                Text("Set Length")
                    .font(RCFont.medium(16))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 18)
            
            HorizontalDurationPicker(selection: $selectedMinutes, horizontalPadding: 18)
        }
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image("MusicNotes")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundColor(.white)
                    Text("Tune Your Playlist")
                        .font(RCFont.medium(16))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Button(action: resetFilters) {
                    Text("Reset")
                        .font(RCFont.regular(14))
                        .foregroundColor(Color(hex: 0xFF3333))
                }
                .opacity(hasActiveFilters ? 1.0 : 0.4)
                .disabled(!hasActiveFilters)
            }
            
            // Genre chips
            FlowLayout(spacing: 8, runSpacing: 8) {
                ForEach(Genre.allCases) { genre in
                    SetupFilterChip(
                        title: genre.displayName,
                        isSelected: selectedGenres.contains(genre),
                        onTap: { toggleGenre(genre) }
                    )
                }
            }
            
            // Decade chips
            FlowLayout(spacing: 8, runSpacing: 8) {
                ForEach(Decade.allCases) { decade in
                    SetupFilterChip(
                        title: decade.displayName,
                        isSelected: selectedDecades.contains(decade),
                        onTap: { toggleDecade(decade) }
                    )
                }
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Helpers
    
    private var hasActiveFilters: Bool {
        !selectedGenres.isEmpty || !selectedDecades.isEmpty
    }
    
    private func resetFilters() {
        selectedGenres = []
        selectedDecades = []
    }
    
    private func toggleGenre(_ genre: Genre) {
        if selectedGenres.contains(genre) {
            selectedGenres.remove(genre)
        } else {
            selectedGenres.insert(genre)
        }
    }
    
    private func toggleDecade(_ decade: Decade) {
        if selectedDecades.contains(decade) {
            selectedDecades.remove(decade)
        } else {
            selectedDecades.insert(decade)
        }
    }
    
    private func createWorkout() {
        onCreateWorkout(selectedTemplate, selectedMinutes, selectedGenres, selectedDecades)
    }
}

// MARK: - Workout Template Card

private struct WorkoutTemplateCard: View {
    let template: RunTemplateType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Background image
                Image(backgroundAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 270, height: 180)
                
                // Gradient overlay for text readability
                LinearGradient(
                    colors: [Color.black.opacity(0.7), Color.clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
                
                // Content
                VStack(alignment: .leading, spacing: 20) {
                    Spacer()
                    
                    HStack(alignment: .bottom) {
                        Text(template.rawValue)
                            .font(RCFont.medium(20))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Intensity bar image
                        Image(intensityBarAssetName)
                            .padding(.bottom, 3)
                    }
                    
                    Text(shortDescription)
                        .font(RCFont.regular(15))
                        .foregroundColor(.white.opacity(0.8))
                        .lineSpacing(4)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
                
                // Selection stroke (inside the ZStack so it clips with content)
                if isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white, lineWidth: 2)
                }
            }
            .frame(width: 270, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
    
    private var backgroundAssetName: String {
        switch template {
        case .light: return "light"
        case .tempo: return "tempo"
        case .hiit: return "hiit"
        case .intervals: return "intervals"
        case .pyramid: return "pyramid"
        case .kicker: return "kicker"
        }
    }
    
    private var shortDescription: String {
        switch template {
        case .light:
            return "Relaxed, steady pace. Ideal for recovery or getting moving without effort."
        case .tempo:
            return "Moderate, confident effort where you lock into a smooth, consistent rhythm."
        case .hiit:
            return "Playful fartlek with alternating easy and harder segments (one easy, one hard)."
        case .intervals:
            return "Longer fartlek with two easy segments followed by two harder ones."
        case .pyramid:
            return "Gradually build to your toughest effort in the middle, then ease back down."
        case .kicker:
            return "Steady run that ends with a hard push in the final stretch."
        }
    }
    
    private var intensityBarAssetName: String {
        switch template {
        case .light: return "lightbar"
        case .tempo: return "tempobar"
        case .hiit: return "hiitbar"
        case .intervals: return "intervalbar"
        case .pyramid: return "pyramidbar"
        case .kicker: return "kickerbar"
        }
    }
}

// MARK: - Horizontal Duration Picker

private struct HorizontalDurationPicker: View {
    @Binding var selection: Int
    var horizontalPadding: CGFloat = 0
    
    // Match settings: 20 to 120 in 5-minute increments
    private let values: [Int] = Array(stride(from: 20, through: 120, by: 5))
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(values, id: \.self) { value in
                        let isSelected = selection == value
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selection = value
                            }
                        }) {
                            Text("\(value)")
                                .font(isSelected ? RCFont.semiBold(18) : RCFont.medium(18))
                                .foregroundColor(isSelected ? .black : .white)
                                .frame(width: 48, height: 48)
                                .background(isSelected ? Color.white : Color.white.opacity(0.05))
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.05), lineWidth: 1)
                                )
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .id(value)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
            .onAppear {
                // Scroll to selected value on appear
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.none) {
                        proxy.scrollTo(selection, anchor: .center)
                    }
                }
            }
            .onChange(of: selection) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Setup Filter Chip

private struct SetupFilterChip: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(isSelected ? RCFont.semiBold(16) : RCFont.medium(16))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(isSelected ? Color.white : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.05), lineWidth: 1)
                )
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
