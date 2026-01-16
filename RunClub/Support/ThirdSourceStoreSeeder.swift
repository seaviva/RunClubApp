//
//  ThirdSourceStoreSeeder.swift
//  RunClub
//
//  Copies or updates a prebuilt thirdsource SwiftData store from the app bundle
//  into Application Support. Supports first-run seed, versioned updates,
//  and back-compat with playlists.store filenames in the bundle.
//

import Foundation

enum ThirdSourceStoreSeeder {
    private static let versionDefaultsKey = "thirdsourceBundleVersion"
    private static let forceReloadKey = "thirdsourceForceReload"

    struct BundleVersion: Codable {
        let version: String
    }

    static func seedOrUpdateIfNeeded() {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(for: .applicationSupportDirectory,
                                           in: .userDomainMask,
                                           appropriateFor: nil,
                                           create: true) else { return }
        // Destination triplet
        let destMain = appSupport.appendingPathComponent("thirdsource.store")
        let destWal = appSupport.appendingPathComponent("thirdsource.store-wal")
        let destShm = appSupport.appendingPathComponent("thirdsource.store-shm")

        let bundle = Bundle.main
        // Preferred names in bundle
        let srcMain = bundle.url(forResource: "thirdsource.store", withExtension: nil, subdirectory: "ThirdSource")
            ?? bundle.url(forResource: "thirdsource.store", withExtension: nil)
        let srcWal = bundle.url(forResource: "thirdsource.store-wal", withExtension: nil, subdirectory: "ThirdSource")
            ?? bundle.url(forResource: "thirdsource.store-wal", withExtension: nil)
        let srcShm = bundle.url(forResource: "thirdsource.store-shm", withExtension: nil, subdirectory: "ThirdSource")
            ?? bundle.url(forResource: "thirdsource.store-shm", withExtension: nil)
        // Back-compat: accept playlists.store* filenames for third source
        let compatMain = bundle.url(forResource: "playlists.store", withExtension: nil, subdirectory: "ThirdSource")
            ?? bundle.url(forResource: "playlists.store", withExtension: nil)
        let compatWal = bundle.url(forResource: "playlists.store-wal", withExtension: nil, subdirectory: "ThirdSource")
            ?? bundle.url(forResource: "playlists.store-wal", withExtension: nil)
        let compatShm = bundle.url(forResource: "playlists.store-shm", withExtension: nil, subdirectory: "ThirdSource")
            ?? bundle.url(forResource: "playlists.store-shm", withExtension: nil)

        let havePreferred = srcMain != nil
        let haveCompat = compatMain != nil
        guard havePreferred || haveCompat else {
            // Nothing to seed; silently return
            return
        }
        // Choose sources (prefer explicit thirdsource.*)
        let useMain = srcMain ?? compatMain
        let useWal = srcWal ?? compatWal
        let useShm = srcShm ?? compatShm

        // Determine if we should seed/update
        let isFirstRun = !fm.fileExists(atPath: destMain.path)
        let forceReload = UserDefaults.standard.bool(forKey: forceReloadKey)
        let bundleVersion = loadBundleVersion()
        let currentVersion = UserDefaults.standard.string(forKey: versionDefaultsKey)
        let isNewerVersion: Bool = {
            guard let b = bundleVersion else { return false }
            guard let cur = currentVersion else { return true } // anything is newer than nil
            // Simple lexicographic compare is fine for date-stamped or semver tags
            return b.version.compare(cur, options: .numeric) == .orderedDescending
        }()
        // Seed/update only if needed; avoid touching live stores otherwise
        if !(isFirstRun || forceReload || isNewerVersion) {
            return
        }
        // Clear dest triplet before copying
        try? fm.removeItem(at: destMain)
        try? fm.removeItem(at: destWal)
        try? fm.removeItem(at: destShm)
        // Copy main
        if let src = useMain {
            do { try fm.copyItem(at: src, to: destMain); print("ThirdSourceSeeder: copied thirdsource.store") }
            catch { print("ThirdSourceSeeder: failed to copy main: \(error)") }
        }
        // WAL/SHM are optional; SQLite will create if missing
        if let wal = useWal {
            do { try fm.copyItem(at: wal, to: destWal); print("ThirdSourceSeeder: copied thirdsource.store-wal") }
            catch { print("ThirdSourceSeeder: failed to copy wal: \(error)") }
        }
        if let shm = useShm {
            do { try fm.copyItem(at: shm, to: destShm); print("ThirdSourceSeeder: copied thirdsource.store-shm") }
            catch { print("ThirdSourceSeeder: failed to copy shm: \(error)") }
        }
        // Record version state
        if let b = bundleVersion { UserDefaults.standard.set(b.version, forKey: versionDefaultsKey) }
        if forceReload { UserDefaults.standard.set(false, forKey: forceReloadKey) }
    }

    static func markForceReload() {
        UserDefaults.standard.set(true, forKey: forceReloadKey)
    }

    private static func loadBundleVersion() -> BundleVersion? {
        // Look for ThirdSource/version.json or root version.json
        let bundle = Bundle.main
        let url = bundle.url(forResource: "version", withExtension: "json", subdirectory: "ThirdSource")
            ?? bundle.url(forResource: "version", withExtension: "json")
        guard let url else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(BundleVersion.self, from: data)
        } catch {
            print("ThirdSourceSeeder: failed to read version.json: \(error)")
            return nil
        }
    }
}


