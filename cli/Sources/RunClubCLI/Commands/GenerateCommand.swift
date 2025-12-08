import ArgumentParser
import Foundation

/// Generate command - runs playlist generation and outputs JSON
struct GenerateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate a playlist and output results as JSON"
    )
    
    // MARK: - Arguments
    
    @Option(name: .long, help: "Run template (light, tempo, hiit, intervals, pyramid, kicker)")
    var template: String = "tempo"
    
    @Option(name: .long, help: "Target run duration in minutes")
    var minutes: Int = 30
    
    @Option(name: .long, help: "Comma-separated genre filters (Pop, Rock & Alt, etc.)")
    var genres: String = ""
    
    @Option(name: .long, help: "Comma-separated decade filters (70s, 80s, 90s, 00s, 10s, 20s)")
    var decades: String = ""
    
    @Flag(name: .long, help: "Pretty-print JSON output")
    var pretty: Bool = false
    
    @Flag(name: .long, help: "Include debug lines in output")
    var debug: Bool = true
    
    // MARK: - Execution
    
    @MainActor
    func run() async throws {
        // Parse template
        guard let templateType = RunTemplateType(rawValue: template.lowercased()) else {
            throw ValidationError("Invalid template '\(template)'. Valid options: light, tempo, hiit, intervals, pyramid, kicker")
        }
        
        // Parse genres
        let genreList: [Genre] = genres.isEmpty ? [] : genres.split(separator: ",").compactMap { genreName in
            let name = genreName.trimmingCharacters(in: .whitespaces)
            return parseGenre(name)
        }
        
        // Parse decades
        let decadeList: [Decade] = decades.isEmpty ? [] : decades.split(separator: ",").compactMap { decadeName in
            let name = decadeName.trimmingCharacters(in: .whitespaces)
            return parseDecade(name)
        }
        
        // Initialize data bridge
        let bridge: DataBridge
        do {
            bridge = try DataBridge()
        } catch {
            let errorOutput = ErrorOutput(
                error: "Failed to initialize data bridge",
                details: error.localizedDescription
            )
            outputJSON(errorOutput, pretty: pretty)
            throw ExitCode.failure
        }
        
        // Create generator and run
        let generator = LocalGenerator(bridge: bridge)
        
        do {
            var output = try generator.generateDryRun(
                template: templateType,
                runMinutes: minutes,
                genres: genreList,
                decades: decadeList
            )
            
            // Strip debug lines if not requested
            if !debug {
                output = GenerationOutput(
                    template: output.template,
                    runMinutes: output.runMinutes,
                    genres: output.genres,
                    decades: output.decades,
                    trackIds: output.trackIds,
                    artistIds: output.artistIds,
                    efforts: output.efforts,
                    sources: output.sources,
                    totalSeconds: output.totalSeconds,
                    minSeconds: output.minSeconds,
                    maxSeconds: output.maxSeconds,
                    warmupSeconds: output.warmupSeconds,
                    mainSeconds: output.mainSeconds,
                    cooldownSeconds: output.cooldownSeconds,
                    warmupTarget: output.warmupTarget,
                    mainTarget: output.mainTarget,
                    cooldownTarget: output.cooldownTarget,
                    preflightUnplayable: output.preflightUnplayable,
                    swapped: output.swapped,
                    removed: output.removed,
                    market: output.market,
                    slots: output.slots,
                    avgTempoFit: output.avgTempoFit,
                    avgSlotFit: output.avgSlotFit,
                    avgGenreAffinity: output.avgGenreAffinity,
                    rediscoveryPct: output.rediscoveryPct,
                    uniqueArtists: output.uniqueArtists,
                    neighborRelaxSlots: output.neighborRelaxSlots,
                    lockoutBreaks: output.lockoutBreaks,
                    sourceLikes: output.sourceLikes,
                    sourcePlaylists: output.sourcePlaylists,
                    sourceThird: output.sourceThird,
                    debugLines: [],
                    generatedAt: output.generatedAt
                )
            }
            
            outputJSON(output, pretty: pretty)
            
        } catch {
            let errorOutput = ErrorOutput(
                error: "Generation failed",
                details: error.localizedDescription
            )
            outputJSON(errorOutput, pretty: pretty)
            throw ExitCode.failure
        }
    }
    
    // MARK: - Helpers
    
    private func parseGenre(_ name: String) -> Genre? {
        let lowered = name.lowercased()
        switch lowered {
        case "pop": return .pop
        case "hip-hop", "hip-hop & rap", "hiphop", "rap": return .hipHopRap
        case "rock", "rock & alt", "alternative": return .rockAlt
        case "electronic", "electronic & dance", "edm", "dance": return .electronic
        case "indie", "indie & alternative": return .indie
        case "r&b", "rnb", "r&b & soul", "soul": return .rnb
        case "country", "country & folk", "folk": return .country
        case "latin": return .latin
        case "jazz", "jazz & blues", "blues": return .jazzBlues
        case "classical", "classical & soundtrack", "soundtrack": return .classicalSoundtrack
        default: return nil
        }
    }
    
    private func parseDecade(_ name: String) -> Decade? {
        let cleaned = name.lowercased().replacingOccurrences(of: "'", with: "")
        switch cleaned {
        case "70s", "1970s", "seventies": return .seventies
        case "80s", "1980s", "eighties": return .eighties
        case "90s", "1990s", "nineties": return .nineties
        case "00s", "2000s", "oughts": return .twoThousands
        case "10s", "2010s", "tens": return .twentyTens
        case "20s", "2020s", "twenties": return .twentyTwenties
        default: return nil
        }
    }
    
    private func outputJSON<T: Encodable>(_ value: T, pretty: Bool) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        
        if let data = try? encoder.encode(value),
           let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    }
}

// MARK: - Error Output

struct ErrorOutput: Codable {
    let error: String
    let details: String
}
