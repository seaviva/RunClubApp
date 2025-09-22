//
//  RootView.swift
//  RunClub
//
//  Created by Christian Vivadelli on 8/15/25.
//

import SwiftUI
import UIKit
import SwiftData

struct RootView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.modelContext) private var modelContext
    @AppStorage("onboardingComplete") private var onboardingComplete: Bool = false
    @StateObject private var crawlCoordinator = CrawlCoordinator()
    @EnvironmentObject var progressStore: CrawlProgressStore
    @State private var showCompletionToast: Bool = false
    @State private var completionText: String = ""

    var body: some View {
        Group {
            if !auth.isAuthorized {
                LoginSplashView()
            } else if !onboardingComplete {
                OnboardingFlowView(onDone: { onboardingComplete = true })
            } else {
                ZStack(alignment: .top) {
                    HomeView()
                        .environmentObject(crawlCoordinator)
                        .environmentObject(progressStore)
                }
                .safeAreaInset(edge: .top) {
                    Group {
                        if progressStore.isRunning {
                            CrawlToast(progress: progressStore) {
                                Task { await crawlCoordinator.cancel() }
                            }
                        } else if showCompletionToast {
                            CompletionToast(text: completionText)
                        }
                    }
                }
            }
        }
        .onOpenURL { url in
            auth.handleRedirect(url: url)
            SpotifyPlaybackController.handleRedirectURL(url)
        }
        .task(id: auth.isAuthorized) {
            guard auth.isAuthorized else { return }
            await crawlCoordinator.configure(auth: auth, modelContext: modelContext, progressStore: progressStore)
            await crawlCoordinator.startIfNeeded()
        }
        .onChange(of: progressStore.isRunning) { running in
            if !running {
                Task {
                    let count = (try? modelContext.fetch(FetchDescriptor<CachedTrack>()).count) ?? 0
                    await MainActor.run {
                        completionText = "Library cached: \(count) tracks"
                        withAnimation { showCompletionToast = true }
                    }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run { withAnimation { showCompletionToast = false } }
                }
            }
        }
    }
}

// Expose a weak shared handle so services can fetch tokens without tight coupling
extension RootView {
    static weak var sharedAuth: AuthService?
}

private struct CrawlToast: View {
    @ObservedObject var progress: CrawlProgressStore
    let onCancel: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("Syncing liked songs…")
                    .font(RCFont.medium(14))
                Text(progress.tracksTotal > 0 ? "\(progress.tracksDone)/\(progress.tracksTotal)" : "\(progress.tracksDone)")
                    .font(RCFont.regular(13))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            Button(action: { onCancel() }) {
                Text("Cancel")
                    .font(RCFont.medium(15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white, lineWidth: 1)
                    )
            }
        }
        .padding(12)
        .background(Color.blue.opacity(1.0))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

private struct CompletionToast: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text(text)
                .font(RCFont.medium(14))
            Spacer()
        }
        .padding(12)
        .background(Color.black.opacity(0.8))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
