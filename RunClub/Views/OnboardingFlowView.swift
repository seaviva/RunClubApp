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
    @State private var runsWheelSelection: Int = 3

    var body: some View {
        ZStack {
            Color(hex: 0xF0F0F0).ignoresSafeArea()
            VStack(alignment: .center, spacing: 24) {
                headerBar
                Group {
                    switch step {
                    case 0: intro
                    case 1: runsPerWeekStep
                    default: durationStep
                    }
                }
                .padding(.top, 18)
                Spacer()
                Button(action: primaryAction) {
                    Text(step == 2 ? "GET RUNNING" : "CONTINUE")
                        .font(RCFont.semiBold(17))
                }
                .buttonStyle(PrimaryFilledButtonStyle())
                .disabled(!isPrimaryEnabled)
            }
            .foregroundColor(.black)
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

    private var headerBar: some View {
        HStack {
            Button(action: { if step > 0 { step -= 1 } }) {
                Image(systemName: "chevron.left").foregroundColor(.black)
            }
            .opacity(step > 0 ? 1 : 0)
            Spacer()
        }
        .padding(.top, 12)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to RunClub")
                .font(RCFont.medium(36))
                .padding(.top, 6)
                .lineSpacing(6)
            Text("Running doesn’t need to be complicated. Forget heart-rate zones, endless training plans, and walls of stats.")
                .font(RCFont.regular(17))
                .padding(.top, 24)
                .lineSpacing(6)
            Text("And music? Choosing songs shouldn’t be harder than the run itself.")
                .font(RCFont.regular(17))
                .lineSpacing(6)
            Text("RunClub takes the thinking out of it. One tap gives you a run plan guided by the energy of the music. Simple, fun, and a chance to re-discover the music you already love.")
                .font(RCFont.regular(17))
                .lineSpacing(6)
            Text("Let's make running simple & fun again.")
                .font(RCFont.medium(17))
                .foregroundColor(.orange)
                .lineSpacing(6)
            Spacer()
        }
        
    }

    private var runsPerWeekStep: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How many runs per week?")
                .font(RCFont.medium(36))
                .lineSpacing(6)
            Text("We’ll make a basic run plan based on this, but you can change it any time in settings.")
                .foregroundColor(.black.opacity(0.4))
                .font(RCFont.regular(16))
                .padding(.top, 24)
                .lineSpacing(6)
            ZStack {
                NumberWheelPicker(selection: $runsWheelSelection,
                                   values: Array(1...7),
                                   rowHeight: 83,
                                   fontSize: 32,
                                   textColor: UIColor.black)
                // Cover default selection background from UIPickerView
                Rectangle()
                    .fill(Color(hex: 0xF0F0F0))
                    .frame(height: 86)
                    .cornerRadius(14)
                    .allowsHitTesting(false)
                Circle()
                    .fill(Color.white)
                    .frame(width: 83, height: 83)
                    .overlay(
                        Text("\(runsWheelSelection)")
                            .font(RCFont.medium(32))
                            .foregroundColor(.black)
                    )
                    .allowsHitTesting(false)
            }
            .frame(height: 360)
            .onAppear {
                if tempRunsPerWeek == nil { tempRunsPerWeek = 3 }
                runsWheelSelection = tempRunsPerWeek ?? 3
            }
            .onChange(of: runsWheelSelection) { newValue in
                tempRunsPerWeek = newValue
            }
            Spacer()
        }
        //.padding(.horizontal, 20)
    }

    private var durationStep: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How long do you want to run?")
                .font(RCFont.medium(36))
                .lineSpacing(6)
            Text("This just sets the default, duration can be changed at any time. We’ll use 1.5× for 'long & easy' runs.")
                .foregroundColor(.black.opacity(0.4))
                .font(RCFont.regular(16))
                .padding(.top, 24)
                .lineSpacing(6)
            VStack(spacing: 12) {
                ForEach(DurationCategory.allCases) { cat in
                    Button(action: { tempDuration = cat }) {
                        VStack(spacing: 4) {
                            Text(title(for: cat))
                                .font(RCFont.medium(24))
                                .foregroundColor(tempDuration == cat ? .white : .black)
                            Text(rangeLabel(for: cat))
                                .font(RCFont.regular(13))
                                .foregroundColor(tempDuration == cat ? Color.white.opacity(0.6) : Color.black.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(tempDuration == cat ? Color.black : Color.white)
                        .cornerRadius(100)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 60)
            Spacer()
        }
    }

    private func title(for cat: DurationCategory) -> String {
        switch cat { case .short: return "Short"; case .medium: return "Medium"; case .long: return "Long" }
    }

    private func rangeLabel(for cat: DurationCategory) -> String {
        let min = cat.minMinutes
        let max = cat.maxMinutes
        return "\(min)-\(max) MIN"
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


