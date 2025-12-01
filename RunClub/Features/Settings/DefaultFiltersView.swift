//
//  DefaultFiltersView.swift
//  RunClub
//

import SwiftUI

struct DefaultFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultGenres") private var defaultGenresData: Data = Data()
    @AppStorage("defaultDecades") private var defaultDecadesData: Data = Data()
    
    @State private var genres: Set<Genre> = []
    @State private var decades: Set<Decade> = []
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                // Header with back button
                ZStack {
                    Text("DEFAULT FILTERS")
                        .font(RCFont.light(14))
                        .foregroundColor(.white)
                    
                    HStack {
                        Button(action: { 
                            saveFilters()
                            dismiss() 
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Back")
                                    .font(RCFont.regular(16))
                            }
                            .foregroundColor(.white)
                        }
                        Spacer()
                        
                        // Clear all button
                        if !genres.isEmpty || !decades.isEmpty {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    genres.removeAll()
                                    decades.removeAll()
                                }
                            }) {
                                Text("CLEAR")
                                    .font(RCFont.regular(14))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Genre filters section
                        Text("GENRE FILTERS")
                            .font(RCFont.regular(13))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        
                        FlowLayout(spacing: 6, runSpacing: 6) {
                            ForEach(Genre.allCases, id: \.self) { genre in
                                let binding = Binding<Bool>(
                                    get: { genres.contains(genre) },
                                    set: { newValue in 
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            if newValue { 
                                                genres.insert(genre) 
                                            } else { 
                                                genres.remove(genre) 
                                            }
                                        }
                                    }
                                )
                                DefaultFilterChip(title: genre.displayName, isSelected: binding)
                            }
                        }
                        
                        // Decade filters section
                        Text("DECADE FILTERS")
                            .font(RCFont.regular(13))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, 28)
                            .padding(.bottom, 4)
                        
                        FlowLayout(spacing: 6, runSpacing: 6) {
                            ForEach(Decade.allCases, id: \.self) { decade in
                                let binding = Binding<Bool>(
                                    get: { decades.contains(decade) },
                                    set: { newValue in 
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            if newValue { 
                                                decades.insert(decade) 
                                            } else { 
                                                decades.remove(decade) 
                                            }
                                        }
                                    }
                                )
                                DefaultFilterChip(title: decade.displayName, isSelected: binding)
                            }
                        }
                        
                        // Explanation text
                        Text("These filters will be applied by default when generating a run playlist. You can override them during the playlist generation flow.")
                            .font(RCFont.light(13))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, 32)
                            .padding(.bottom, 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            loadFilters()
        }
        .onDisappear {
            saveFilters()
        }
    }
    
    private func loadFilters() {
        if let decoded = try? JSONDecoder().decode(Set<Genre>.self, from: defaultGenresData) {
            genres = decoded
        }
        if let decoded = try? JSONDecoder().decode(Set<Decade>.self, from: defaultDecadesData) {
            decades = decoded
        }
    }
    
    private func saveFilters() {
        if let encoded = try? JSONEncoder().encode(genres) {
            defaultGenresData = encoded
        }
        if let encoded = try? JSONEncoder().encode(decades) {
            defaultDecadesData = encoded
        }
    }
}

// Filter chip styled for default filters view
private struct DefaultFilterChip: View {
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

// Helper to get the count of default filters from anywhere
struct DefaultFiltersHelper {
    static func getDefaultGenres() -> Set<Genre> {
        guard let data = UserDefaults.standard.data(forKey: "defaultGenres"),
              let decoded = try? JSONDecoder().decode(Set<Genre>.self, from: data) else {
            return []
        }
        return decoded
    }
    
    static func getDefaultDecades() -> Set<Decade> {
        guard let data = UserDefaults.standard.data(forKey: "defaultDecades"),
              let decoded = try? JSONDecoder().decode(Set<Decade>.self, from: data) else {
            return []
        }
        return decoded
    }
    
    static func getTotalCount() -> Int {
        return getDefaultGenres().count + getDefaultDecades().count
    }
}

