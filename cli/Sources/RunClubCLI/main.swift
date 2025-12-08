import ArgumentParser
import Foundation

/// RunClubCLI - Command-line interface for playlist generation testing
///
/// This CLI wraps the LocalGenerator to enable headless playlist generation
/// for the agent system to evaluate and improve the algorithm.
@main
struct RunClubCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "RunClubCLI",
        abstract: "RunClub playlist generation CLI for algorithm testing",
        version: "1.0.0",
        subcommands: [GenerateCommand.self, InfoCommand.self],
        defaultSubcommand: GenerateCommand.self
    )
}

/// Info command - shows information about available data
struct InfoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show information about available data stores"
    )
    
    @MainActor
    func run() async throws {
        let bridge = try DataBridge()
        let stats = try bridge.getDataStats()
        
        print("=== RunClub Data Info ===")
        print("Likes Store:")
        print("  Tracks: \(stats.likesTrackCount)")
        print("  Features: \(stats.likesFeaturesCount)")
        print("  Artists: \(stats.likesArtistCount)")
        print("")
        print("Playlists Store:")
        print("  Tracks: \(stats.playlistsTrackCount)")
        print("  Features: \(stats.playlistsFeaturesCount)")
        print("  Artists: \(stats.playlistsArtistCount)")
        print("")
        print("Third Source Store:")
        print("  Tracks: \(stats.thirdSourceTrackCount)")
        print("  Features: \(stats.thirdSourceFeaturesCount)")
        print("  Artists: \(stats.thirdSourceArtistCount)")
        print("")
        print("Total available tracks: \(stats.totalTracks)")
        print("Tracks with features: \(stats.tracksWithFeatures)")
    }
}

