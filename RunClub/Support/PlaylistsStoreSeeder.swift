//
//  PlaylistsStoreSeeder.swift
//  RunClub
//
//  Copies a prebuilt playlists SwiftData store from the app bundle into
//  Application Support on first run. Idempotent and safe if files already exist.
//

import Foundation

enum PlaylistsStoreSeeder {
    static func seedIfNeeded() {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(for: .applicationSupportDirectory,
                                           in: .userDomainMask,
                                           appropriateFor: nil,
                                           create: true) else {
            return
        }
        let names = ["playlists.store", "playlists.store-wal", "playlists.store-shm"]
        let destMain = appSupport.appendingPathComponent("playlists.store")
        if fm.fileExists(atPath: destMain.path) {
            return // already present; do not overwrite
        }
        for name in names {
            // Try root of bundle, then ThirdSource/ subdirectory
            let src = Bundle.main.url(forResource: name, withExtension: nil)
                ?? Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "ThirdSource")
            if let src {
                let dst = appSupport.appendingPathComponent(name)
                // Remove any stale partial file; ignore errors
                if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
                do {
                    try fm.copyItem(at: src, to: dst)
                    print("PlaylistsStoreSeeder: copied \(name) to \(dst.lastPathComponent)")
                } catch {
                    print("PlaylistsStoreSeeder: failed to copy \(name): \(error)")
                }
            } else {
                // Not found in bundle; log once for the main store file
                if name == "playlists.store" {
                    print("PlaylistsStoreSeeder: \(name) not found in bundle (root or ThirdSource/). Skipping seeding.")
                }
            }
        }
        // No hard failure if WAL/SHM are missing; SQLite will create as needed.
    }
}


