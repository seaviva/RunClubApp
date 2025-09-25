//
//  RunTemplateType.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import Foundation

enum RunTemplateType: String, Codable, CaseIterable, Identifiable, Hashable {
    case rest = "Rest"
    case easyRun = "Light"
    case strongSteady = "Tempo"
    case longEasy = "Long & Easy"
    case shortWaves = "HIIT"
    case longWaves = "Intervals"
    case pyramid = "Pyramid"
    case kicker = "Kicker"

    var id: String { rawValue }
}


