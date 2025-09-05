//
//  OnboardingFlowView.swift
//  RunClub
//
//  Created by Assistant on 8/19/25.
//

import SwiftUI
import UIKit

struct OnboardingFlowView: View {
    @AppStorage("runsPerWeek") private var runsPerWeek: Int = 3
    @AppStorage("preferredDurationCategory") private var preferredDurationRaw: String = DurationCategory.medium.rawValue
    let onDone: () -> Void
    @State private var step: Int = 0
    @State private var tempRunsPerWeek: Int? = nil
    @State private var tempDuration: DurationCategory? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                progressDots
                switch step {
                case 0: intro
                case 1: runsPerWeekStep
                default: durationStep
                }
                Spacer()
                Button(action: primaryAction) {
                    Text(step == 2 ? "Complete" : "Continue")
                        .font(RCFont.semiBold(18))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(Color.clear)
                }
                .buttonStyle(PrimaryFilledButtonStyle())
                .padding(.bottom, 24)
                .disabled(!isPrimaryEnabled)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .onAppear {
                #if canImport(UIKit)
                let fams = UIFont.familyNames.sorted()
                print("FONTS families count:", fams.count)
                for fam in fams {
                    let names = UIFont.fontNames(forFamilyName: fam)
                    print("FONTS family:", fam, "names:", names)
                }
                print("FONTS IBM Plex Sans:", UIFont.fontNames(forFamilyName: "IBM Plex Sans"))
                #endif
            }
        }
    }

    private var progressDots: some View {
        HStack(spacing: 24) {
            ForEach(0..<3) { i in
                Rectangle()
                    .fill(i == step ? Color.white : Color.white.opacity(0.25))
                    .frame(width: 64, height: 3)
                    .cornerRadius(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WELCOME")
                .font(RCFont.medium(32))
                .padding(.top, 8)
            Divider().background(Color.white)
            Text("Hey there,\n\nEver struggle to figure out what to listen to? This is for you.")
                .font(RCFont.regular(16))
                .padding(.top, 24)
            Text("We generate custom playlists on the fly for your next run, all based on your likes (and other stuff).")
                .foregroundColor(.white)
                .font(RCFont.regular(16))
            Text("You can create your own custom run plan or playlist anytime.")
                .foregroundColor(.white)
                .font(RCFont.regular(16))
            Spacer()
        }
        
    }

    private var runsPerWeekStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RUNS PER WEEK")
                .font(RCFont.medium(32))
            Divider().background(Color.white)
            Text("Just let us know how many times you want to run a week – helps us recommend better daily runs for your progress")
                .foregroundColor(.white.opacity(0.6))
                .font(RCFont.regular(16))
                .padding(.top, 24)
            HStack(spacing: 16) {
                ForEach([2,3,4,5], id: \.self) { n in
                    Button(action: { tempRunsPerWeek = n }) {
                        Text("\(n)")
                            .font(RCFont.semiBold(24))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SelectableTertiaryButtonStyle(isSelected: tempRunsPerWeek == n))
                }
            }
            Spacer()
        }
        //.padding(.horizontal, 20)
    }

    private var durationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RUN LENGTH")
                .font(RCFont.medium(32))
            Divider().background(Color.white)
            Text("How long do you want these runs to be generally? We’ll use 1.5× for long runs.")
                .foregroundColor(.white.opacity(0.6))
                .font(RCFont.regular(16))
                .padding(.top, 24)
            VStack(spacing: 16) {
                ForEach(DurationCategory.allCases) { cat in
                    Button(action: { tempDuration = cat }) {
                        Text(cat.displayName.uppercased())
                            .font(RCFont.semiBold(24))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SelectableTertiaryButtonStyle(isSelected: tempDuration == cat))
                }
            }
            Spacer()
        }
    }

    private func primaryAction() {
        if step == 0 { step = 1; return }
        if step == 1 {
            if let n = tempRunsPerWeek { runsPerWeek = n }
            step = 2
            return
        }
        if step == 2 {
            if let d = tempDuration { preferredDurationRaw = d.rawValue }
            onDone()
        }
    }

    private var isPrimaryEnabled: Bool {
        switch step {
        case 0: return true
        case 1: return tempRunsPerWeek != nil
        default: return tempDuration != nil
        }
    }
}


