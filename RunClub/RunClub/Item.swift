//
//  Item.swift
//  RunClub
//
//  Created by Christian Vivadelli on 8/15/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
