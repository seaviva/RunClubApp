//
//  CustomizeRunView.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import SwiftUI

struct CustomizeRunView: View {
    @Environment(\.dismiss) private var dismiss
    // Current selections
    @State private var selectedTemplate: RunTemplateType
    @State private var selectedDuration: DurationCategory
    @State private var selectedGenres: Set<Genre> = []
    @State private var selectedDecades: Set<Decade> = []
    @State private var customMinutes: Int? = nil
    // No prompt for now per design

    // For reset behavior
    private let initialTemplateValue: RunTemplateType
    private let initialDurationValue: DurationCategory
    private let initialGenresValue: Set<Genre>
    private let initialDecadesValue: Set<Decade>
    private let initialCustomMinutes: Int?
    private let recommendedTemplateForToday: RunTemplateType?
    

    // UI state
    @State private var showTemplatePicker: Bool = false
    @State private var showDurationPicker: Bool = false
    @State private var templateBoxFrame: CGRect = .zero
    @State private var durationBoxFrame: CGRect = .zero
    @State private var activeTab: Tab = .run

    let onSave: (RunTemplateType, DurationCategory, Set<Genre>, Set<Decade>, String, Int?) -> Void

    init(initialTemplate: RunTemplateType,
         initialDuration: DurationCategory,
         initialGenres: Set<Genre> = [],
         initialDecades: Set<Decade> = [],
         initialPrompt: String = "",
         initialCustomMinutes: Int? = nil,
         recommendedTemplateOrRest: RunTemplateType? = nil,
         onSave: @escaping (RunTemplateType, DurationCategory, Set<Genre>, Set<Decade>, String, Int?) -> Void) {
        _selectedTemplate = State(initialValue: initialTemplate)
        _selectedDuration = State(initialValue: initialDuration)
        _selectedGenres = State(initialValue: initialGenres)
        _selectedDecades = State(initialValue: initialDecades)
        _customMinutes = State(initialValue: initialCustomMinutes)
        // Prompt not used
        initialTemplateValue = initialTemplate
        initialDurationValue = initialDuration
        initialGenresValue = initialGenres
        initialDecadesValue = initialDecades
        self.initialCustomMinutes = initialCustomMinutes
        self.recommendedTemplateForToday = recommendedTemplateOrRest
        
        self.onSave = onSave
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                // Header per new design
                ZStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .foregroundColor(.white)
                                .imageScale(.medium)
                        }
                        Spacer()
                        Button(action: {
                            onSave(selectedTemplate, selectedDuration, selectedGenres, selectedDecades, "", customMinutes)
                            dismiss()
                        }) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.white)
                                .imageScale(.medium)
                        }
                        .disabled(!isDirty)
                        .opacity(isDirty ? 1.0 : 0.5)
                    }
                    Text("CHOOSE WORKOUT TYPE")
                        .font(RCFont.light(15))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            // Content switches by tab (Run tab removed; selection now on Home)
            Group {
                switch activeTab {
                case .time:
                        timeTab
                    case .filter:
                        filterTab
                    }
                }
                .animation(.easeInOut, value: activeTab)

                Spacer(minLength: 0)

                // Bottom tabs (remove Run)
                HStack(spacing: 0) {
                    tabItem(title: "LENGTH", systemImage: "timer", selected: activeTab == .time) { activeTab = .time }
                    Spacer()
                    tabItem(title: "FILTER", systemImage: "music.note.list", selected: activeTab == .filter) { activeTab = .filter }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .overlay(Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1), alignment: .top)
            }
        }
        .coordinateSpace(name: "sheet")
        // No dropdown overlays in the new design
    }

    private func resetSelections() {
        selectedTemplate = initialTemplateValue
        selectedDuration = initialDurationValue
        selectedGenres = []
        selectedDecades = []
        customMinutes = initialCustomMinutes
        durationWheelTouched = false
        durationWheelSelection = customMinutes ?? 30
    }

    private func templateDescription(_ template: RunTemplateType) -> String {
        switch template {
        case .rest:
            return "Take a day to recover. Light movement, mobility, or full rest — your call."
        case .easyRun:
            return "Steady easy run for casual and recovery runs"
        case .strongSteady:
            return "Steady moderately hard effort"
        case .longEasy:
            return "Steady long easy run for building endurance"
        case .shortWaves:
            return "Alternating easy and hard for 1 song each"
        case .longWaves:
            return "Alternating easy and hard for 2 songs each"
        case .pyramid:
            return "Gradual build, peak, then descend in effort"
        case .kicker:
            return "Steady easy run with a high energy ending"
        }
    }

    private func durationDescription(_ duration: DurationCategory) -> String {
        switch duration {
        case .short: return "20 - 30 min"
        case .medium: return "30 - 45 min"
        case .long: return "45 - 60 min"
        }
    }

    // MARK: - Tabs
    private enum Tab { case time, filter }

    // Removed templateCarouselOrder; not needed without Run tab

    // Removed old tabBar with Run

    private func tabItem(title: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundColor(.white)
                    .opacity(selected ? 1.0 : 0.5)
                Text(title)
                    .font(RCFont.medium(14))
                    .foregroundColor(.white)
                    .opacity(selected ? 1.0 : 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    // Removed runTab since selection happens on Home

    // Time tab: wheel picker for custom minutes (optional override)
    @State private var durationWheelSelection: Int = 30
    @State private var durationWheelTouched: Bool = false

    private var timeTab: some View {
        VStack(spacing: 24) {
            Text("LENGTH")
                .font(RCFont.regular(13))
                .foregroundColor(.white.opacity(0.6))

            DurationWheel(selection: Binding<Int>(
                get: { durationWheelSelection },
                set: { minutes in
                    durationWheelSelection = minutes
                    durationWheelTouched = true
                    customMinutes = minutes
                }
            ), values: Array(stride(from: 20, through: 120, by: 5)))
            .onAppear {
                durationWheelSelection = customMinutes ?? 30
                durationWheelTouched = false
            }

            Text(durationWheelTouched || customMinutes != nil ? "Custom: \(durationWheelSelection) min" : durationDescription(selectedDuration))
                .font(RCFont.medium(16))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 20)
    }

    // Filter tab: reuse chips
    private var filterTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FILTER PLAYLIST")
                .font(RCFont.regular(13))
                .foregroundColor(.white.opacity(0.6))

            FlowLayout(spacing: 6, runSpacing: 6) {
                ForEach(Genre.allCases, id: \.self) { genre in
                    let binding = Binding<Bool>(
                        get: { selectedGenres.contains(genre) },
                        set: { newValue in
                            if newValue { selectedGenres.insert(genre) } else { selectedGenres.remove(genre) }
                        }
                    )
                    FilterChip(title: genre.displayName, isSelected: binding)
                }
            }

            FlowLayout(spacing: 6, runSpacing: 6) {
                ForEach(Decade.allCases, id: \.self) { decade in
                    let binding = Binding<Bool>(
                        get: { selectedDecades.contains(decade) },
                        set: { newValue in
                            if newValue { selectedDecades.insert(decade) } else { selectedDecades.remove(decade) }
                        }
                    )
                    FilterChip(title: decade.displayName, isSelected: binding)
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - DurationWheel component
struct DurationWheel: View {
    @Binding var selection: Int
    var values: [Int] = Array(stride(from: 20, through: 120, by: 5))

    var body: some View {
        ZStack {
            NumberWheelPicker(selection: $selection,
                               values: values,
                               rowHeight: 60,
                               fontSize: 28,
                               textColor: UIColor.white)
            // Highlight band
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 64)
                .cornerRadius(12)
                .allowsHitTesting(false)
        }
        .frame(height: 300)
    }
}

// Preference keys for capturing dropdown box frames
private struct TemplateFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct DurationFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct DropdownMenu: View {
    let items: [(String, String)]
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { idx in
                Button(action: { onSelect(idx) }) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(items[idx].0)
                                .font(RCFont.medium(18))
                                .foregroundColor(.white)
                            Text(items[idx].1)
                                .font(RCFont.medium(13))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding(16)
                    .frame(height: 56)
                    .background(Color(hex: 0xBD4095))
                }
                .buttonStyle(.plain)
                if idx < items.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .background(Color(hex: 0xBD4095))
        .padding(.top, -4)
    }
}

// Simple flow layout for left-aligned wrapping
// iOS 16+ SwiftUI Layout for left-aligned wrapping with spacing, hugging intrinsic widths
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var runSpacing: CGFloat = 6

    init(spacing: CGFloat = 6, runSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.runSpacing = runSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            let additional = (currentWidth == 0 ? size.width : spacing + size.width)
            if currentWidth + additional > maxWidth {
                // wrap to next row
                totalHeight += rowHeight + runSpacing
                currentWidth = size.width
                rowHeight = size.height
            } else {
                currentWidth += additional
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        let width = maxWidth.isFinite ? maxWidth : currentWidth
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            let neededWidth = (x == bounds.minX ? size.width : spacing + size.width)
            if x + neededWidth > bounds.maxX {
                // wrap
                x = bounds.minX
                y += rowHeight + runSpacing
                rowHeight = 0
            }
            let placeX = (x == bounds.minX ? x : x + spacing)
            sub.place(at: CGPoint(x: placeX, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x = placeX + size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}
// MARK: - UI Components

private struct DropdownBox: View {
    var title: String
    var subtitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(RCFont.medium(18))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(RCFont.medium(13))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(Color(hex: 0xBD4095))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

private struct FilterChip: View {
    let title: String
    @Binding var isSelected: Bool

    var body: some View {
        Button(action: { isSelected.toggle() }) {
            Text(title)
                .font(RCFont.medium(15))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(height: 40, alignment: .center)
                .background(isSelected ? Color.white.opacity(0.25) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(isSelected ? 0.0 : 0.25), lineWidth: 1)
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helpers

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Dirty tracking
private extension CustomizeRunView {
    var isDirty: Bool {
        if selectedTemplate != initialTemplateValue { return true }
        if selectedDuration != initialDurationValue { return true }
        if selectedGenres != initialGenresValue { return true }
        if selectedDecades != initialDecadesValue { return true }
        if customMinutes != initialCustomMinutes { return true }
        return false
    }
}


