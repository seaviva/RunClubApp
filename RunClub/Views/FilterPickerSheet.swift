//
//  FilterPickerSheet.swift
//  RunClub
//
//

import SwiftUI

struct FilterPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var genres: Set<Genre>
    @State private var decades: Set<Decade>
    @AppStorage("useRecommendations") private var useRecommendations: Bool = true
    @AppStorage("recommendationsWeight") private var recommendationsWeight: Double = 0.4
    private let originalGenres: Set<Genre>
    private let originalDecades: Set<Decade>
    let onDone: (Set<Genre>, Set<Decade>) -> Void

    init(initialGenres: Set<Genre>, initialDecades: Set<Decade>, onDone: @escaping (Set<Genre>, Set<Decade>) -> Void) {
        _genres = State(initialValue: initialGenres)
        _decades = State(initialValue: initialDecades)
        self.originalGenres = initialGenres
        self.originalDecades = initialDecades
        self.onDone = onDone
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                let hasChanges = (genres != originalGenres) || (decades != originalDecades)
                ZStack {
                    Text("EDIT RUN PLAYLIST")
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
                        Spacer()
                        Button(action: { onDone(genres, decades); dismiss() }) {
                            Image("check")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.white)
                                .opacity(hasChanges ? 1.0 : 0.25)
                        }
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("GENRE FILTERS")
                            .font(RCFont.regular(13))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                        FlowLayout(spacing: 6, runSpacing: 6) {
                            ForEach(Genre.allCases, id: \.self) { genre in
                                let binding = Binding<Bool>(
                                    get: { genres.contains(genre) },
                                    set: { newValue in if newValue { genres.insert(genre) } else { genres.remove(genre) } }
                                )
                                SheetFilterChip(title: genre.displayName, isSelected: binding)
                            }
                        }
                        Text("DECADE FILTERS")
                            .font(RCFont.regular(13))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, 28)
                            .padding(.bottom, 4)
                        FlowLayout(spacing: 6, runSpacing: 6) {
                            ForEach(Decade.allCases, id: \.self) { decade in
                                let binding = Binding<Bool>(
                                    get: { decades.contains(decade) },
                                    set: { newValue in if newValue { decades.insert(decade) } else { decades.remove(decade) } }
                                )
                                SheetFilterChip(title: decade.displayName, isSelected: binding)
                            }
                        }

                        // Recommendations controls
                        Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1).padding(.top, 28)
                        HStack {
                            Text("Use Recommendations")
                                .font(RCFont.regular(15))
                            Spacer()
                            Toggle("", isOn: $useRecommendations)
                                .labelsHidden()
                        }
                        .foregroundColor(.white)
                        if useRecommendations {
                            HStack(spacing: 12) {
                                Text("Likes")
                                    .font(RCFont.regular(13))
                                    .foregroundColor(.white.opacity(0.7))
                                Slider(value: $recommendationsWeight, in: 0...1, step: 0.05)
                                    .tint(.white)
                                Text("Recs")
                                    .font(RCFont.regular(13))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            let likesPct = Int(round((1 - recommendationsWeight) * 100))
                            let recsPct = 100 - likesPct
                            Text("Mix: \(likesPct)% Likes • \(recsPct)% Recs")
                                .font(RCFont.regular(13))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .foregroundColor(.white)
        }
    }
}


private struct SheetFilterChip: View {
    let title: String
    @Binding var isSelected: Bool

    var body: some View {
        Button(action: { isSelected.toggle() }) {
            Text(title)
                .font(RCFont.regular(16))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 24)
                .frame(height: 48, alignment: .center)
                .background(isSelected ? Color.white : Color.white.opacity(0.10))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}


