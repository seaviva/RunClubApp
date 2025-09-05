//
//  DurationCategory.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import Foundation

enum DurationCategory: String, Codable, CaseIterable, Identifiable {
    case short
    case medium
    case long

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .short: return "Short (20–30 min)"
        case .medium: return "Medium (30–45 min)"
        case .long: return "Long (45–60 min)"
        }
    }

    var minMinutes: Int {
        switch self { case .short: return 20; case .medium: return 30; case .long: return 45 }
    }

    var maxMinutes: Int {
        switch self { case .short: return 30; case .medium: return 45; case .long: return 60 }
    }

    var midpointMinutes: Int {
        switch self { case .short: return 25; case .medium: return 37; case .long: return 53 }
    }
}


