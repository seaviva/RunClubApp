//
//  ReccoIdCache.swift
//  RunClub
//
//  Simple disk-backed cache for Spotify→Recco ID mappings.
//

import Foundation

final class ReccoIdCache {
    private var map: [String: String] = [:]
    private let url: URL
    private let lock = NSLock()

    init(filename: String = "recco_id_cache.json") {
        let fm = FileManager.default
        if let docs = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            url = docs.appendingPathComponent(filename)
        } else {
            url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        }
        load()
    }

    private func load() {
        lock.lock(); defer { lock.unlock() }
        do {
            let data = try Data(contentsOf: url)
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                map = dict
            }
        } catch { /* cold start ok */ }
    }

    private func persist() {
        lock.lock(); defer { lock.unlock() }
        do {
            let data = try JSONSerialization.data(withJSONObject: map, options: [.sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch { /* best-effort */ }
    }

    func get(_ spotifyId: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return map[spotifyId]
    }

    func merge(_ newMap: [String: String]) {
        guard !newMap.isEmpty else { return }
        lock.lock()
        for (k, v) in newMap { map[k] = v }
        lock.unlock()
        persist()
    }
}


