//
//  Config.swift
//  RunClub
//
//  Created by Christian Vivadelli on 8/15/25.
//

enum Config {
    static let clientID = "6b4e25209b8d451ea246192ce6fbdca7"
    static let redirectURI = "runclub://auth-callback"
    static let scopes = [
        "user-read-email","user-read-private",
        "user-library-read","user-top-read",
        "playlist-modify-public","playlist-modify-private",
        // Playback control + metadata for in-app start/pause/resume and track info
        "user-modify-playback-state","user-read-playback-state","user-read-currently-playing",
        // Required for Spotify App Remote control
        "app-remote-control"
    ].joined(separator: " ")

    // External audio-features provider (ReccoBeats)
    // No API key required per docs; base URL:
    // https://api.reccobeats.com
    static let reccoBeatsBaseURL = "https://api.reccobeats.com"
}
