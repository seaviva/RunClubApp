//
//  PlaylistsCoordinator.swift
//  RunClub
//
//  Orchestrates playlist catalog refresh and sync of selected playlists.
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
final class PlaylistsCoordinator: ObservableObject {
    @Published var progress: CrawlProgressStore
    private var crawler: PlaylistsCrawler?
    private var runningTask: Task<Void, Never>? = nil
    private let repo = PlaylistsRepository()

    init(progress: CrawlProgressStore = CrawlProgressStore()) {
        self.progress = progress
    }

    func configure(auth: AuthService, progressStore: CrawlProgressStore? = nil, likesContext: ModelContext? = nil) async {
        if let ps = progressStore { self.progress = ps }
        let spotify = SpotifyService()
        await auth.refreshIfNeeded()
        spotify.accessTokenProvider = { AuthService.overrideToken() ?? (AuthService.sharedTokenSync() ?? "") }
        self.crawler = PlaylistsCrawler(spotify: spotify, repository: repo, progress: self.progress, context: PlaylistsDataStack.shared.context, likesContext: likesContext ?? ModelContext(PlaylistsDataStack.shared.container))
        // Ensure synthetic Recently Played exists in catalog (unselected by default)
        let ctx = PlaylistsDataStack.shared.context
        let existing = try? ctx.fetch(FetchDescriptor<CachedPlaylist>(predicate: #Predicate { $0.id == "recently-played" })).first
        if let rp = existing {
            // Ensure metadata stays in sync with product expectations
            rp.name = "Recently Played (last 50)"
            // Before any sync, show 50 to mirror the API limit / UX intent.
            if rp.totalTracks == 0 {
                rp.totalTracks = 50
            }
            try? ctx.save()
        } else {
            let p = CachedPlaylist(id: "recently-played",
                                   name: "Recently Played (last 50)",
                                   ownerId: "",
                                   ownerName: "",
                                   isOwner: true,
                                   isPublic: false,
                                   collaborative: false,
                                   imageURL: nil,
                                   totalTracks: 50, // Display 50 tracks pre-sync to match "last 50" semantics.
                                   snapshotId: nil,
                                   selectedForSync: false, // user opts in explicitly
                                   lastSyncedAt: nil,
                                   isSynthetic: true)
            ctx.insert(p)
            try? ctx.save()
        }
    }

    /// Refreshes the playlist catalog (owned + followed) into the Playlists store.
    func refreshCatalog() async {
        // Catalog refresh does not require the crawler; do not early-return if missing.
        let ctx = PlaylistsDataStack.shared.context
        let spotifyMirror = SpotifyService()
        spotifyMirror.accessTokenProvider = { AuthService.overrideToken() ?? (AuthService.sharedTokenSync() ?? "") }
        let meId = (try? await spotifyMirror.currentUserId()) ?? ""
        do {
            let items = try await spotifyMirror.getAllUserPlaylists()
            var models: [CachedPlaylist] = []
            for it in items {
                models.append(CachedPlaylist(id: it.id,
                                             name: it.name,
                                             ownerId: it.ownerId,
                                             ownerName: it.ownerName,
                                             isOwner: it.ownerId == meId,
                                             isPublic: it.isPublic,
                                             collaborative: it.collaborative,
                                             imageURL: it.imageURL,
                                             totalTracks: it.totalTracks,
                                             snapshotId: it.snapshotId,
                                             selectedForSync: false,
                                             lastSyncedAt: nil,
                                             isSynthetic: false))
            }
            try repo.upsertPlaylists(models)
            print("[PLAYLISTS] catalog updated — found: \(models.count)")
            await MainActor.run { [weak self] in self?.progress.message = "Playlists catalog updated (\(models.count))" }
        } catch {
            print("[PLAYLISTS] catalog refresh failed: \(error)")
            await MainActor.run { [weak self] in self?.progress.message = "Catalog refresh failed" }
        }
    }

    /// Sync selected playlists and Recently Played into the Playlists store.
    func refreshSelected() async {
        // Ensure crawler exists; construct on-demand if needed
        if crawler == nil {
            let spotify = SpotifyService()
            spotify.accessTokenProvider = { AuthService.overrideToken() ?? (AuthService.sharedTokenSync() ?? "") }
            self.crawler = PlaylistsCrawler(spotify: spotify,
                                            repository: repo,
                                            progress: self.progress,
                                            context: PlaylistsDataStack.shared.context,
                                            likesContext: ModelContext(PlaylistsDataStack.shared.container))
        }
        guard let crawler else {
            print("[PLAYLISTS] refreshSelected aborted — crawler unavailable")
            return
        }
        let ctx = PlaylistsDataStack.shared.context
        let selected = (try? ctx.fetch(FetchDescriptor<CachedPlaylist>(predicate: #Predicate { $0.selectedForSync == true }))) ?? []
        print("[PLAYLISTS] refreshSelected — selected playlists:", selected.count, "ids:", selected.map { $0.id }.prefix(5))
        if selected.isEmpty {
            await MainActor.run { [weak self] in
                self?.progress.message = "No playlists selected"
                self?.progress.isRunning = false
            }
            return
        }
        // Reset playable content (keep playlists and selections)
        do { try await MainActor.run { try PlaylistsDataStack.shared.resetContent() } }
        catch { print("[PLAYLISTS] resetContent failed:", error.localizedDescription) }
        // Run crawl in background to decouple from view/task lifetimes
        runningTask?.cancel()
        runningTask = Task {
            print("[PLAYLISTS] crawl starting")
            await crawler.refreshSelected()
            await MainActor.run { [weak self] in
                print("[PLAYLISTS] crawl finished")
                self?.runningTask = nil
            }
        }
    }

    /// Quick sync: Only sync playlists that have changed (based on snapshot_id)
    func quickSync() async {
        // Ensure crawler exists
        if crawler == nil {
            let spotify = SpotifyService()
            spotify.accessTokenProvider = { AuthService.overrideToken() ?? (AuthService.sharedTokenSync() ?? "") }
            self.crawler = PlaylistsCrawler(spotify: spotify,
                                            repository: repo,
                                            progress: self.progress,
                                            context: PlaylistsDataStack.shared.context,
                                            likesContext: ModelContext(PlaylistsDataStack.shared.container))
        }
        guard let crawler else {
            print("[PLAYLISTS] quickSync aborted — crawler unavailable")
            return
        }
        
        runningTask?.cancel()
        runningTask = Task {
            print("[PLAYLISTS] incremental sync starting")
            await crawler.incrementalSync()
            await MainActor.run { [weak self] in
                print("[PLAYLISTS] incremental sync finished")
                self?.runningTask = nil
            }
        }
    }
    
    func cancel() async {
        runningTask?.cancel()
        await crawler?.cancel()
    }
}
