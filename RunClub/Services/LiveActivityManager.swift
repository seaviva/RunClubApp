//
//  LiveActivityManager.swift
//  RunClub
//
//  Stub manager for Live Activities. Will be fleshed out later; for now,
//  guard iOS version and compile as no-op on simulator.
//

import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    func start(now: String, next: String?) async {
        // Disabled: Live Activities gated off until entitlement is available
    }

    func update(now: String, next: String?) async {
        // Disabled
    }

    func end() async {
        // Disabled
    }
}


