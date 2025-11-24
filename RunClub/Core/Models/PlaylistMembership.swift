//
//  PlaylistMembership.swift
//  RunClub
//
//  Row linking a playlist to a track (many-to-many via composite id).
//

import Foundation
import SwiftData

@Model
final class PlaylistMembership {
    @Attribute(.unique) var id: String // composite: "\(playlistId)|\(trackId)"
    var playlistId: String
    var trackId: String
    var addedAt: Date?

    init(playlistId: String, trackId: String, addedAt: Date?) {
        self.id = "\(playlistId)|\(trackId)"
        self.playlistId = playlistId
        self.trackId = trackId
        self.addedAt = addedAt
    }
}


