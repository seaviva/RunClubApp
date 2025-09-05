//
//  Decade.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import Foundation

enum Decade: String, CaseIterable, Identifiable, Codable {
    case seventies = "70s"
    case eighties = "80s"
    case nineties = "90s"
    case twoThousands = "00s"
    case twentyTens = "10s"
    case twentyTwenties = "20s"

    var id: String { rawValue }

    var displayName: String { rawValue }
}


