//
//  RunTemplateType.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import Foundation

enum RunTemplateType: String, Codable, CaseIterable, Identifiable {
    case easyRun = "Easy Run"
    case strongSteady = "Strong & Steady"
    case longEasy = "Long & Easy"
    case shortWaves = "Short Waves"
    case longWaves = "Long Waves"
    case pyramid = "Pyramid"
    case kicker = "Kicker"

    var id: String { rawValue }
}


