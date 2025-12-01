//
//  RunTemplateType.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import Foundation

enum RunTemplateType: String, Codable, CaseIterable, Identifiable, Hashable {
    case light = "Light"
    case tempo = "Tempo"
    case hiit = "HIIT"
    case intervals = "Intervals"
    case pyramid = "Pyramid"
    case kicker = "Kicker"

    var id: String { rawValue }
}


