//
//  CachedPlaylist.swift
//  RunClub
//
//  SwiftData entity describing a Spotify playlist metadata row.
//

import Foundation
import SwiftData

@Model
final class CachedPlaylist {
    @Attribute(.unique) var id: String // Spotify playlist ID or synthetic "recently-played"
    var name: String
    var ownerId: String
    var ownerName: String
    var isOwner: Bool
    var isPublic: Bool
    var collaborative: Bool
    var imageURL: String?
    var totalTracks: Int
    var snapshotId: String?
    var selectedForSync: Bool
    var lastSyncedAt: Date?
    var isSynthetic: Bool // true for "recently-played"

    init(id: String,
         name: String,
         ownerId: String,
         ownerName: String,
         isOwner: Bool,
         isPublic: Bool,
         collaborative: Bool,
         imageURL: String?,
         totalTracks: Int,
         snapshotId: String?,
         selectedForSync: Bool,
         lastSyncedAt: Date? = nil,
         isSynthetic: Bool = false) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.ownerName = ownerName
        self.isOwner = isOwner
        self.isPublic = isPublic
        self.collaborative = collaborative
        self.imageURL = imageURL
        self.totalTracks = totalTracks
        self.snapshotId = snapshotId
        self.selectedForSync = selectedForSync
        self.lastSyncedAt = lastSyncedAt
        self.isSynthetic = isSynthetic
    }
}


