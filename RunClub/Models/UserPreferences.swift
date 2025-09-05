//
//  UserPreferences.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import Foundation

struct UserPreferences: Codable, Equatable {
    var runsPerWeek: Int
    var preferredDuration: DurationCategory
}


