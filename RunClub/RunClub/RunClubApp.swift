//
//  RunClubApp.swift
//  RunClub
//
//  Created by Christian Vivadelli on 8/15/25.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct RunClubApp: App {
    @StateObject private var auth = AuthService()
    @StateObject private var progressStore = CrawlProgressStore()
    private let spotify = SpotifyService() // keep for future injection
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CachedTrack.self,
            AudioFeature.self,
            CachedArtist.self,
            CrawlState.self,
            CompletedRun.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Attempt recovery by removing incompatible store and recreating
            let fm = FileManager.default
            if let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
                let storeURL = appSupport.appendingPathComponent("default.store")
                try? fm.removeItem(at: storeURL)
                try? fm.removeItem(at: storeURL.appendingPathExtension("wal"))
                try? fm.removeItem(at: storeURL.appendingPathExtension("shm"))
                do {
                    return try ModelContainer(for: schema, configurations: [configuration])
                } catch {
                    fatalError("Could not create ModelContainer after recovery: \(error)")
                }
            }
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(progressStore)
                .onAppear { RootView.sharedAuth = auth }
                .task {
                    // Restore saved Spotify credentials and refresh if needed
                    auth.loadFromKeychain()
                    await auth.refreshIfNeeded()
                }
                .onAppear {
                    // Allow notifications to alert while app is foregrounded
                    UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    private override init() {}
    // Show alert banners while app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}
