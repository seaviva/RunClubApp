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
    @AppStorage("has_override_token") private var hasOverrideToken: Bool = false
    @StateObject private var crawlCoordinator = CrawlCoordinator()
    @EnvironmentObject var progressStore: LikesProgressStore
    @State private var showCompletionToast: Bool = false
    @State private var completionText: String = ""
    // Add recommendations coordinator + use shared progress from environment
    @StateObject private var recsCoordinator = RecommendationsCoordinator()
    @EnvironmentObject var recsProgress: RecsProgressStore
    // Toast dismissal state (does not cancel the job)
    @State private var hideLikesToast: Bool = false
    @State private var hideRecsToast: Bool = false

    var body: some View {
        Group {
            let isAuthorizedEffective = auth.isAuthorized || hasOverrideToken
            if !isAuthorizedEffective {
                LoginSplashView()
            } else if !onboardingComplete {
                OnboardingFlowView(onDone: { onboardingComplete = true })
            } else {
                ZStack(alignment: .top) {
                    HomeView()
                        .environmentObject(crawlCoordinator)
                        .environmentObject(progressStore)
                        .environmentObject(recsCoordinator)
                }
                // Overlay the toast(s) without affecting layout; allow swipe-to-hide
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        if progressStore.isRunning && !hideLikesToast {
                            CrawlToast(title: "Syncing liked songs…", progress: progressStore, onCancel: {
                                Task { await crawlCoordinator.cancel() }
                            }, onDismiss: { hideLikesToast = true })
                            .onAppear { print("[LIKES_TOAST] running=\(progressStore.isRunning) done=\(progressStore.tracksDone) total=\(progressStore.tracksTotal) id=\(ObjectIdentifier(progressStore))") }
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if recsProgress.isRunning && !hideRecsToast {
                            CrawlToast(title: "Syncing recommendations…", progress: recsProgress, onCancel: {
                                Task { await recsCoordinator.cancel() }
                            }, onDismiss: { hideRecsToast = true })
                            .onAppear { print("[RECS_TOAST] running=\(recsProgress.isRunning) done=\(recsProgress.tracksDone) total=\(recsProgress.tracksTotal) id=\(ObjectIdentifier(recsProgress))") }
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if showCompletionToast && !(progressStore.isRunning || recsProgress.isRunning) {
                            CompletionToast(text: completionText)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 12)
                    .animation(.easeInOut, value: progressStore.isRunning)
                    .animation(.easeInOut, value: recsProgress.isRunning)
                }
            }
        }
        .onAppear { progressStore.debugName = "LIKES"; recsProgress.debugName = "RECS" }
        .onChange(of: recsProgress.isRunning) { running in
            print("[RECS_STATE] running=\(running) likesId=\(ObjectIdentifier(progressStore)) recsId=\(ObjectIdentifier(recsProgress)))")
        }
        .task(id: auth.isAuthorized) {
            let isAuthorizedEffective = auth.isAuthorized || hasOverrideToken
            guard isAuthorizedEffective else { return }
            await crawlCoordinator.configure(auth: auth, modelContext: modelContext, progressStore: progressStore)
            await crawlCoordinator.startIfNeeded()
            // Configure and kick off recommendations in parallel (only if empty)
            await recsCoordinator.configure(auth: auth, progressStore: recsProgress)
            await recsCoordinator.startIfNeeded(targetCount: 1000)
            // Scheduled refresh: once per week start a background recommendations refresh
            scheduleWeeklyRecsRefresh()
        }
        .onChange(of: progressStore.isRunning) { running in
            if running { hideLikesToast = false }
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
    var title: String = "Syncing liked songs…"
    @ObservedObject var progress: CrawlProgressStore
    let onCancel: () -> Void
    let onDismiss: () -> Void
    @State private var offsetY: CGFloat = 0
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
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
        .offset(y: offsetY)
        .gesture(
            DragGesture().onChanged { value in
                // Allow dragging up to hide
                if value.translation.height < 0 { offsetY = value.translation.height }
            }.onEnded { value in
                if value.translation.height < -30 {
                    withAnimation { offsetY = -200 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
                } else {
                    withAnimation { offsetY = 0 }
                }
            }
        )
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

// MARK: - Weekly recs refresh scheduling (lightweight)
extension RootView {
    private func scheduleWeeklyRecsRefresh() {
        let key = "recs_last_refresh"
        let now = Date()
        let last = UserDefaults.standard.object(forKey: key) as? Date
        let sevenDays: TimeInterval = 7 * 24 * 3600
        if last == nil || now.timeIntervalSince(last!) > sevenDays {
            Task { await recsCoordinator.refresh(targetCount: 300) }
            UserDefaults.standard.set(now, forKey: key)
        }
    }
}
