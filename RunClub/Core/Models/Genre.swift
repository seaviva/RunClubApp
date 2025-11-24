//
//  Genre.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import Foundation

enum Genre: String, CaseIterable, Identifiable, Codable {
    case pop = "Pop"
    case hipHopRap = "Hip-Hop & Rap"
    case rockAlt = "Rock & Alt"
    case electronic = "Electronic & Dance"
    case indie = "Indie"
    case rnb = "R&B & Soul"
    case country = "Country & Americana"
    case latin = "Latin & Reggaeton"
    case jazzBlues = "Jazz & Blues"
    case classicalSoundtrack = "Classical & Soundtrack"

    var id: String { rawValue }

    var displayName: String { rawValue }
}


