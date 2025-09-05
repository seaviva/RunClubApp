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
    // No prompt for now per design

    // For reset behavior
    private let initialTemplateValue: RunTemplateType
    private let initialDurationValue: DurationCategory
    private let initialGenresValue: Set<Genre>
    private let initialDecadesValue: Set<Decade>
    

    // UI state
    @State private var showTemplatePicker: Bool = false
    @State private var showDurationPicker: Bool = false
    @State private var templateBoxFrame: CGRect = .zero
    @State private var durationBoxFrame: CGRect = .zero

    let onSave: (RunTemplateType, DurationCategory, Set<Genre>, Set<Decade>, String) -> Void

    init(initialTemplate: RunTemplateType,
         initialDuration: DurationCategory,
         initialGenres: Set<Genre> = [],
         initialDecades: Set<Decade> = [],
         initialPrompt: String = "",
         onSave: @escaping (RunTemplateType, DurationCategory, Set<Genre>, Set<Decade>, String) -> Void) {
        _selectedTemplate = State(initialValue: initialTemplate)
        _selectedDuration = State(initialValue: initialDuration)
        _selectedGenres = State(initialValue: initialGenres)
        _selectedDecades = State(initialValue: initialDecades)
        // Prompt not used
        initialTemplateValue = initialTemplate
        initialDurationValue = initialDuration
        initialGenresValue = initialGenres
        initialDecadesValue = initialDecades
        
        self.onSave = onSave
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xA70072), Color(hex: 0xD4004A)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 32) {
                // Header
                HStack(spacing: 10) {
                    Text("CUSTOMIZE")
                        .font(RCFont.medium(32))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: resetSelections) {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.white)
                            .imageScale(.large)
                    }
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .imageScale(.large)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .overlay(Rectangle().fill(Color.white).frame(height: 1).padding(.horizontal, 20), alignment: .bottom)
                .padding(.bottom, 8)

                // Template section
                VStack(alignment: .leading, spacing: 8) {
                    Text("TEMPLATE")
                        .font(RCFont.regular(13))
                        .foregroundColor(.white.opacity(0.6))

                    DropdownBox(title: selectedTemplate.rawValue,
                                subtitle: templateDescription(selectedTemplate),
                                action: { withAnimation { showTemplatePicker.toggle() } })
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: TemplateFrameKey.self, value: geo.frame(in: .named("sheet")))
                        })
                        .onPreferenceChange(TemplateFrameKey.self) { templateBoxFrame = $0 }
                }
                .padding(.horizontal, 20)

                // Duration section
                VStack(alignment: .leading, spacing: 8) {
                    Text("LENGTH")
                        .font(RCFont.regular(13))
                        .foregroundColor(.white.opacity(0.6))

                    DropdownBox(title: selectedDuration.displayName,
                                subtitle: durationDescription(selectedDuration),
                                action: { withAnimation { showDurationPicker.toggle() } })
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: DurationFrameKey.self, value: geo.frame(in: .named("sheet")))
                        })
                        .onPreferenceChange(DurationFrameKey.self) { durationBoxFrame = $0 }
                }
                .padding(.horizontal, 20)

                // Filters
                VStack(alignment: .leading, spacing: 12) {
                    Text("FILTER PLAYLIST")
                        .font(RCFont.regular(13))
                        .foregroundColor(.white.opacity(0.6))

                    // Genres
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

                    // Decades
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

                Spacer()

                // Save button
                Button("Save") {
                    onSave(selectedTemplate, selectedDuration, selectedGenres, selectedDecades, "")
                    dismiss()
                }
                .buttonStyle(PrimaryFilledButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .coordinateSpace(name: "sheet")
        // Overlay dropdown menus positioned over content so the sheet doesn't expand
        .overlay(alignment: .topLeading) {
            ZStack {
                if showTemplatePicker {
                    DropdownMenu(items: RunTemplateType.allCases.map { ($0.rawValue, templateDescription($0)) }) { index in
                        selectedTemplate = RunTemplateType.allCases[index]
                        withAnimation { showTemplatePicker = false }
                    }
                    .frame(width: max(templateBoxFrame.width, 0))
                    .offset(x: templateBoxFrame.minX, y: templateBoxFrame.maxY + 16)
                }
                if showDurationPicker {
                    DropdownMenu(items: DurationCategory.allCases.map { ($0.displayName, durationDescription($0)) }) { index in
                        selectedDuration = DurationCategory.allCases[index]
                        withAnimation { showDurationPicker = false }
                    }
                    .frame(width: max(durationBoxFrame.width, 0))
                    .offset(x: durationBoxFrame.minX, y: durationBoxFrame.maxY + 16)
                }
            }
        }
    }

    private func resetSelections() {
        selectedTemplate = initialTemplateValue
        selectedDuration = initialDurationValue
        selectedGenres = []
        selectedDecades = []
        
    }

    private func templateDescription(_ template: RunTemplateType) -> String {
        switch template {
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


