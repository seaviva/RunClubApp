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

    init(userId: String, dateKey: String, completedAt: Date = Date()) {
        self.userId = userId
        self.dateKey = dateKey
        self.completedAt = completedAt
        self.id = "\(userId)-\(dateKey)"
    }
}


