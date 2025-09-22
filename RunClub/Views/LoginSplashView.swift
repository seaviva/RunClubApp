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
            VStack(spacing: 16) {
                Spacer()
                ZStack {
                    // Large typographic logo approximation
                    Text("Running made simple.")
                        .font(RCFont.medium(50))
                        .foregroundColor(.white)
                        .lineSpacing(-64)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 210)
                }
                VStack(spacing: 8) {
                    Text("Daily runs guided by custom playlists of your favorite music.")
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.white)
                        .font(RCFont.regular(18))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                }
                Spacer()
                Button(action: { auth.startLogin() }) {
                    HStack(spacing: 10) {
                        Image("SpotifyLogo")
                            .renderingMode(.original)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 22)
                        Text("Continue with Spotify")
                            .font(RCFont.semiBold(17))
                            .foregroundColor(.black)
                    }
                }
                .buttonStyle(SecondaryOutlineButtonStyle())
            }
            .overlay(alignment: .topLeading) {
                Image("runclublogo")
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 28)
                    .padding(24)
            }
        }
    }
}


