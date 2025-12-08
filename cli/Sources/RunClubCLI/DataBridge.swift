import Foundation
import SwiftData

/// DataBridge provides access to the app's SwiftData stores for CLI operations.
///
/// It locates and opens the existing store files created by the iOS/macOS app,
/// allowing headless generation without needing to run the full app.
@MainActor
final class DataBridge {
    
    // MARK: - Properties
    
    /// Primary context for likes data
    let likesContext: ModelContext
    
    /// Context for playlists data
    let playlistsContext: ModelContext
    
    /// Context for third-source data
    let thirdSourceContext: ModelContext
    
    /// Containers (kept alive)
    private let likesContainer: ModelContainer
    private let playlistsContainer: ModelContainer
    private let thirdSourceContainer: ModelContainer
    
    // MARK: - Initialization
    
    init() throws {
        // Find the app's data directory
        let sourceDir = try Self.findDataDirectory()
        
        // Copy stores to temp directory to avoid migration issues with read-only
        let tempDir = try Self.createTempCopy(of: sourceDir)
        
        // Set up schema
        let schema = Schema([
            CachedTrack.self,
            AudioFeature.self,
            CachedArtist.self,
            TrackUsage.self,
            CrawlState.self
        ])
        
        // Open likes store (default container)
        // Note: allowsSave: true on temp copy to permit schema migration
        let likesStoreURL = tempDir.appending(path: "default.store")
        let likesConfig = ModelConfiguration(
            schema: schema,
            url: likesStoreURL
        )
        likesContainer = try ModelContainer(for: schema, configurations: [likesConfig])
        likesContext = ModelContext(likesContainer)
        likesContext.autosaveEnabled = false  // Don't auto-save changes
        
        // Open playlists store
        let playlistsStoreURL = tempDir.appending(path: "playlists.store")
        let playlistsConfig = ModelConfiguration(
            "playlists",
            schema: schema,
            url: playlistsStoreURL
        )
        playlistsContainer = try ModelContainer(for: schema, configurations: [playlistsConfig])
        playlistsContext = ModelContext(playlistsContainer)
        playlistsContext.autosaveEnabled = false
        
        // Open third-source store
        let thirdSourceStoreURL = tempDir.appending(path: "thirdsource.store")
        let thirdSourceConfig = ModelConfiguration(
            "thirdsource",
            schema: schema,
            url: thirdSourceStoreURL
        )
        thirdSourceContainer = try ModelContainer(for: schema, configurations: [thirdSourceConfig])
        thirdSourceContext = ModelContext(thirdSourceContainer)
        thirdSourceContext.autosaveEnabled = false
    }
    
    /// Copy store files to a temporary directory to allow schema migration
    private static func createTempCopy(of sourceDir: URL) throws -> URL {
        let fileManager = FileManager.default
        let tempBase = fileManager.temporaryDirectory.appending(path: "RunClubCLI")
        
        // Clean up old temp if exists
        try? fileManager.removeItem(at: tempBase)
        try fileManager.createDirectory(at: tempBase, withIntermediateDirectories: true)
        
        // Copy each store file and its journal files
        let storeNames = ["default.store", "playlists.store", "thirdsource.store"]
        let journalSuffixes = ["", "-shm", "-wal"]
        
        for storeName in storeNames {
            for suffix in journalSuffixes {
                let fileName = storeName + suffix
                let sourceFile = sourceDir.appending(path: fileName)
                let destFile = tempBase.appending(path: fileName)
                
                if fileManager.fileExists(atPath: sourceFile.path) {
                    try fileManager.copyItem(at: sourceFile, to: destFile)
                }
            }
        }
        
        return tempBase
    }
    
    // MARK: - Data Directory Discovery
    
    /// Find the directory containing SwiftData stores
    private static func findDataDirectory() throws -> URL {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        
        // Priority 1: Explicit environment variable
        if let envPath = ProcessInfo.processInfo.environment["RUNCLUB_DATA_DIR"] {
            let url = URL(fileURLWithPath: envPath)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        
        // Priority 2: App container (macOS sandboxed app)
        let containerPath = home
            .appending(path: "Library/Containers/com.christianvivadelli.RunClub/Data/Library/Application Support")
        if fileManager.fileExists(atPath: containerPath.path) {
            return containerPath
        }
        
        // Priority 3: Standard Application Support
        let appSupportPath = home
            .appending(path: "Library/Application Support/RunClub")
        if fileManager.fileExists(atPath: appSupportPath.path) {
            return appSupportPath
        }
        
        // Priority 4: Group container (for app groups)
        let groupPath = home
            .appending(path: "Library/Group Containers/group.com.runclub/Library/Application Support")
        if fileManager.fileExists(atPath: groupPath.path) {
            return groupPath
        }
        
        // Priority 5: Direct Application Support (non-sandboxed)
        let directAppSupport = home.appending(path: "Library/Application Support")
        let directStoreURL = directAppSupport.appending(path: "default.store")
        if fileManager.fileExists(atPath: directStoreURL.path) {
            return directAppSupport
        }
        
        // Priority 6: Check Xcode Previews/Simulator locations
        let previewsPath = home.appending(path: "Library/Developer/Xcode/UserData/Previews/Simulator Devices")
        if let enumerator = fileManager.enumerator(
            at: previewsPath,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            while let url = enumerator.nextObject() as? URL {
                // Look for directories with all three stores
                if url.lastPathComponent == "Application Support" {
                    let defaultStore = url.appending(path: "default.store")
                    let thirdStore = url.appending(path: "thirdsource.store")
                    if fileManager.fileExists(atPath: defaultStore.path) &&
                       fileManager.fileExists(atPath: thirdStore.path) {
                        return url
                    }
                }
            }
        }
        
        // Priority 7: Check common Xcode derived data locations
        let derivedDataPaths = [
            home.appending(path: "Library/Developer/Xcode/DerivedData"),
        ]
        
        for basePath in derivedDataPaths {
            if let enumerator = fileManager.enumerator(at: basePath, includingPropertiesForKeys: nil) {
                while let url = enumerator.nextObject() as? URL {
                    if url.lastPathComponent == "default.store" && url.path.contains("RunClub") {
                        return url.deletingLastPathComponent()
                    }
                }
            }
        }
        
        throw DataBridgeError.storesNotFound(
            """
            Could not locate SwiftData stores. Please either:
            1. Run the RunClub app at least once to create the data stores
            2. Set RUNCLUB_DATA_DIR environment variable to the directory containing the .store files
            
            Searched locations:
            - \(containerPath.path)
            - \(appSupportPath.path)
            - \(groupPath.path)
            """
        )
    }
    
    // MARK: - Data Access
    
    /// Get statistics about available data
    func getDataStats() throws -> DataStatsOutput {
        let likesTracks = try likesContext.fetch(FetchDescriptor<CachedTrack>())
        let likesFeatures = try likesContext.fetch(FetchDescriptor<AudioFeature>())
        let likesArtists = try likesContext.fetch(FetchDescriptor<CachedArtist>())
        
        let playlistsTracks = try playlistsContext.fetch(FetchDescriptor<CachedTrack>())
        let playlistsFeatures = try playlistsContext.fetch(FetchDescriptor<AudioFeature>())
        let playlistsArtists = try playlistsContext.fetch(FetchDescriptor<CachedArtist>())
        
        let thirdTracks = try thirdSourceContext.fetch(FetchDescriptor<CachedTrack>())
        let thirdFeatures = try thirdSourceContext.fetch(FetchDescriptor<AudioFeature>())
        let thirdArtists = try thirdSourceContext.fetch(FetchDescriptor<CachedArtist>())
        
        // Count unique tracks and those with features
        var allTrackIds = Set<String>()
        var tracksWithFeaturesIds = Set<String>()
        
        let allFeatureIds = Set(likesFeatures.map { $0.trackId })
            .union(playlistsFeatures.map { $0.trackId })
            .union(thirdFeatures.map { $0.trackId })
        
        for track in likesTracks {
            allTrackIds.insert(track.id)
            if allFeatureIds.contains(track.id) {
                tracksWithFeaturesIds.insert(track.id)
            }
        }
        for track in playlistsTracks {
            allTrackIds.insert(track.id)
            if allFeatureIds.contains(track.id) {
                tracksWithFeaturesIds.insert(track.id)
            }
        }
        for track in thirdTracks {
            allTrackIds.insert(track.id)
            if allFeatureIds.contains(track.id) {
                tracksWithFeaturesIds.insert(track.id)
            }
        }
        
        return DataStatsOutput(
            likesTrackCount: likesTracks.count,
            likesFeaturesCount: likesFeatures.count,
            likesArtistCount: likesArtists.count,
            playlistsTrackCount: playlistsTracks.count,
            playlistsFeaturesCount: playlistsFeatures.count,
            playlistsArtistCount: playlistsArtists.count,
            thirdSourceTrackCount: thirdTracks.count,
            thirdSourceFeaturesCount: thirdFeatures.count,
            thirdSourceArtistCount: thirdArtists.count,
            totalTracks: allTrackIds.count,
            tracksWithFeatures: tracksWithFeaturesIds.count
        )
    }
    
    /// Fetch all tracks from likes context
    func fetchLikesTracks() throws -> [CachedTrack] {
        try likesContext.fetch(FetchDescriptor<CachedTrack>())
    }
    
    /// Fetch all audio features from likes context
    func fetchLikesFeatures() throws -> [AudioFeature] {
        try likesContext.fetch(FetchDescriptor<AudioFeature>())
    }
    
    /// Fetch all artists from likes context
    func fetchLikesArtists() throws -> [CachedArtist] {
        try likesContext.fetch(FetchDescriptor<CachedArtist>())
    }
    
    /// Fetch all track usages
    func fetchTrackUsages() throws -> [TrackUsage] {
        try likesContext.fetch(FetchDescriptor<TrackUsage>())
    }
    
    /// Fetch tracks from playlists context
    func fetchPlaylistsTracks() throws -> [CachedTrack] {
        try playlistsContext.fetch(FetchDescriptor<CachedTrack>())
    }
    
    /// Fetch features from playlists context
    func fetchPlaylistsFeatures() throws -> [AudioFeature] {
        try playlistsContext.fetch(FetchDescriptor<AudioFeature>())
    }
    
    /// Fetch artists from playlists context
    func fetchPlaylistsArtists() throws -> [CachedArtist] {
        try playlistsContext.fetch(FetchDescriptor<CachedArtist>())
    }
    
    /// Fetch tracks from third-source context
    func fetchThirdSourceTracks() throws -> [CachedTrack] {
        try thirdSourceContext.fetch(FetchDescriptor<CachedTrack>())
    }
    
    /// Fetch features from third-source context
    func fetchThirdSourceFeatures() throws -> [AudioFeature] {
        try thirdSourceContext.fetch(FetchDescriptor<AudioFeature>())
    }
    
    /// Fetch artists from third-source context
    func fetchThirdSourceArtists() throws -> [CachedArtist] {
        try thirdSourceContext.fetch(FetchDescriptor<CachedArtist>())
    }
}

// MARK: - Errors

enum DataBridgeError: Error, LocalizedError {
    case storesNotFound(String)
    case invalidStoreFormat(String)
    
    var errorDescription: String? {
        switch self {
        case .storesNotFound(let message):
            return "Data stores not found: \(message)"
        case .invalidStoreFormat(let message):
            return "Invalid store format: \(message)"
        }
    }
}
