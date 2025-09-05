//
//  OnboardingView.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("runsPerWeek") private var runsPerWeek: Int = 3
    @AppStorage("preferredDurationCategory") private var preferredDurationRaw: String = DurationCategory.medium.rawValue
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Let’s set up your runs")
                .font(.title).bold()

            VStack(alignment: .leading, spacing: 12) {
                Text("Runs per week")
                    .font(.headline)
                HStack {
                    ForEach([2,3,4,5], id: \.self) { n in
                        Button(action: { runsPerWeek = n }) {
                            Text("\(n)")
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(runsPerWeek == n ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                                .cornerRadius(8)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Preferred duration")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(DurationCategory.allCases) { cat in
                        Button(action: { preferredDurationRaw = cat.rawValue }) {
                            HStack {
                                Image(systemName: preferredDurationRaw == cat.rawValue ? "largecircle.fill.circle" : "circle")
                                Text(cat.displayName)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }

            Button("Continue") { onDone() }
                .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }
}


