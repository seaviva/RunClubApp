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
    @State private var showWebConnect: Bool = false
    @AppStorage("has_override_token") private var hasOverrideToken: Bool = false

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
                Button(action: { showWebConnect = true }) {
                    HStack(spacing: 10) {
                        Image("SpotifyLogo")
                            .renderingMode(.original)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 22)
                        Text("Connect via Juky")
                            .font(RCFont.semiBold(17))
                            .foregroundColor(.black)
                    }
                }
                .buttonStyle(SecondaryOutlineButtonStyle())
                .sheet(isPresented: $showWebConnect) {
                    WebTokenConnectView(onAuth: { _ in
                        print("[AUTH] Web connect success — dismissing sheet")
                        DispatchQueue.main.async { showWebConnect = false }
                        // Optional token probe for diagnostics
                        Task {
                            let spotify = SpotifyService()
                            spotify.accessTokenProvider = { AuthService.overrideToken() ?? "" }
                            if let id = try? await spotify.currentUserId() {
                                print("[AUTH] token probe OK — userId=\(id)")
                            } else {
                                print("[AUTH] token probe FAILED")
                            }
                        }
                    }, onFail: {
                        print("[AUTH] Web connect failure (keep sheet open for user to continue)")
                    })
                }
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
        // Failsafe: if token arrives via any path, auto-dismiss the sheet
        .onChange(of: hasOverrideToken) { newVal in
            if newVal {
                print("[AUTH] has_override_token observed in Splash — dismissing connect sheet")
                DispatchQueue.main.async { showWebConnect = false }
            }
        }
    }
}


