//
//  Config.swift
//  RunClub
//
//  Created by Christian Vivadelli on 8/15/25.
//

enum Config {
    static let clientID = "6b4e25209b8d451ea246192ce6fbdca7"
    static let redirectURI = "runclub://auth-callback"
    // Scopes retained for documentation; Juky requests scopes on our behalf via web.
    static let scopes = [
        "user-read-email","user-read-private",
        "user-library-read","user-library-modify","user-top-read",
        "playlist-read-private","playlist-read-collaborative",
        "playlist-modify-public","playlist-modify-private",
        // Playback control + metadata for in-app start/pause/resume and track info
        "user-modify-playback-state","user-read-playback-state","user-read-currently-playing",
        // Optional for diagnostics
        "user-read-recently-played"
    ].joined(separator: " ")

    // External audio-features provider (ReccoBeats)
    // No API key required per docs; base URL:
    // https://api.reccobeats.com
    static let reccoBeatsBaseURL = "https://api.reccobeats.com"

    // Juky integration constants
    static let jukyWebURL = "https://web.juky.app"
    static let jukyWebViewUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    // Ingestion tuning
    // Remove unconditional sleeps; rely on 429-aware backoff
    static let useFieldsForMeTracks: Bool = true
    static let likesPagePrefetchDepth: Int = 3 // triple-buffer by default
    
    // Legacy ReccoBeats settings (deprecated - kept for backwards compatibility)
    static let featuresMaxConcurrency: Int = 20
    static let reccoResolveBatchSize: Int = 200
    
    // Optimized ReccoBeats batch settings (NEW)
    // Uses GET /v1/audio-features?ids= which accepts Spotify IDs directly
    static let reccoBatchSize: Int = 40           // API limit is 40 IDs per request
    static let reccoWaveConcurrency: Int = 10     // Concurrent requests per wave (tested: 10 avoids rate limits)
    static let reccoWaveDelayMs: UInt64 = 500     // Delay between waves in milliseconds
}
