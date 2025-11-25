//
//  OnboardingFlowView.swift
//  RunClub
//
//  Created by Assistant on 8/19/25.
//

import SwiftUI
import UIKit

struct OnboardingFlowView: View {
    let onDone: () -> Void
    @State private var goToPlaylists: Bool = false
    @State private var currentStepIndex: Int = 0
    
    private let totalSteps: Int = 3

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x040007), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Screen content - fills available space
                    stepView(for: currentStepIndex)
                        .frame(maxHeight: .infinity)
           
                    // Dots
                    dotsIndicator(current: currentStepIndex, total: totalSteps)
                        .padding(.bottom, 44)
                    
                    // Continue button
                    Button(action: continueTapped) {
                        Text("CONTINUE")
                    }
                    .buttonStyle(SecondaryOutlineButtonStyle())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                    
                    // Hidden navigation to playlist flow after last screen
                    NavigationLink(isActive: $goToPlaylists) {
                        PlaylistSelectionView(mode: .onboarding, onContinue: { onDone() })
                    } label: { EmptyView() }
                    .hidden()
                }
                .foregroundColor(.white)
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarBackButtonHidden(true)
        }
    }

    // MARK: - Step Content
    @ViewBuilder
    private func stepView(for index: Int) -> some View {
        switch index {
        case 0:
            firstScreen
        case 1:
            secondScreen
        default:
            thirdScreen
        }
    }
    
    // Generic layout for the three onboarding screens
    private func onboardingScreen(imageName: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Main image
            onboardingImage(imageName)
            
            // Title
            Text(title)
                .font(RCFont.medium(34))
                .foregroundColor(.white)
                .padding(.top, 12)
            
            // Subtext
            Text(subtitle)
                .font(RCFont.regular(17))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 12)
        }
        // Exact spacing between subtext and dots
        .padding(.bottom, 40)
    }
    
    // Loads an image by name; if missing, falls back to "workout" to avoid a blank screen.
    @ViewBuilder
    private func onboardingImage(_ name: String) -> some View {
        #if canImport(UIKit)
        if let ui = UIImage(named: name) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
        } else if let fallback = UIImage(named: "workout") {
            Image(uiImage: fallback)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
        } else {
            // Render an empty placeholder if both primary and fallback images are missing
            Color.clear
                .frame(height: 1)
        }
        #else
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
        #endif
    }
    
    // Screen 1: "pick a workout"
    private var firstScreen: some View {
        onboardingScreen(
            imageName: "workout",
            title: "pick a workout",
            subtitle: "7 simple templates for you to select based on how you’re feeling"
        )
    }
    
    // Screen 2: "set your playlist"
    private var secondScreen: some View {
        onboardingScreen(
            imageName: "filter",
            title: "set your playlist",
            subtitle: "a new playlist for every run, ready to match any mood you’re in"
        )
    }
    
    // Screen 3: "run to the rhythm"
    private var thirdScreen: some View {
        onboardingScreen(
            imageName: "run",
            title: "run to the rhythm",
            subtitle: "let the energy of the music naturally guide your effort"
        )
    }
    
    // MARK: - Dots
    private func dotsIndicator(current: Int, total: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<total, id: \.self) { idx in
                Circle()
                    .fill(idx == current ? Color.white : Color.white.opacity(0.15))
                    .frame(width: 7, height: 7)
            }
        }
    }
    
    // MARK: - Actions
    private func continueTapped() {
        if currentStepIndex < totalSteps - 1 {
            currentStepIndex += 1
        } else {
            goToPlaylists = true
        }
    }

}


