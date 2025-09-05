//
//  LoginSplashView.swift
//  RunClub
//
//  Created by Assistant on 8/19/25.
//

import SwiftUI
import AVFoundation

struct LoginSplashView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        ZStack {
            // Background video (backgroundrun.mp4 in Resources/Video)
            VideoBackgroundView(resourceName: "backgroundrun")
                .ignoresSafeArea()
            Color.black.opacity(0.35).ignoresSafeArea() // darken overlay for legibility
            VStack(spacing: 32) {
                Spacer()
                ZStack {
                    // Large typographic logo approximation
                    Text("RUN\nCLUB")
                        .font(RCFont.thin(120))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-64)
                        .padding(.horizontal, 24)
                        .minimumScaleFactor(0.5)
                }
                VStack(spacing: 8) {
                    Text("Custom playlists for every run")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.6))
                        .font(RCFont.regular(20))
                        .padding(.horizontal, 24)
                }
                Spacer()
                Button(action: { auth.startLogin() }) {
                    Text("Connect Spotify")
                        .font(RCFont.semiBold(18))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(Color.white)
                        .cornerRadius(6)
                        .padding(.horizontal, 24)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
    }
}


