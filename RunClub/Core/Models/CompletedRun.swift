//
//  CompletedRun.swift
//  RunClub
//
//  Created by Assistant on 9/24/25.
//

import Foundation
import SwiftData

@Model
final class CompletedRun {
    @Attribute(.unique) var id: String
    var userId: String
    var dateKey: String // yyyyMMdd
    var completedAt: Date
    // Optional metrics for simplified log
    var elapsedSeconds: Int?
    var distanceMeters: Double?
    var template: String?
    var runMinutes: Int?

    init(userId: String, dateKey: String, completedAt: Date = Date(), elapsedSeconds: Int? = nil, distanceMeters: Double? = nil, template: String? = nil, runMinutes: Int? = nil) {
        self.userId = userId
        self.dateKey = dateKey
        self.completedAt = completedAt
        self.elapsedSeconds = elapsedSeconds
        self.distanceMeters = distanceMeters
        self.template = template
        self.runMinutes = runMinutes
        self.id = "\(userId)-\(dateKey)"
    }
}


