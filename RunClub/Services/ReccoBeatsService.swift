//
//  ReccoBeatsService.swift
//  RunClub
//
//  Created by Assistant on 8/25/25.
//

import Foundation

struct ReccoBeatsAudioFeatures: Decodable {
    // Adapt fields to actual API once documented. Placeholder common audio feature fields
    let tempo: Double?
    let energy: Double?
    let danceability: Double?
    let valence: Double?
    let loudness: Double?
    let key: Int?
    let mode: Int?
    // Accept both time_signature and timeSignature
    let time_signature: Int?

    var timeSignature: Int? { time_signature }
}

final class ReccoBeatsService {
    static let versionTag = "RB-Integration-1"
    private let baseURL: String
    private let apiKey: String?

    init(baseURL: String = Config.reccoBeatsBaseURL, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    // Basic GET with 429-aware retry/backoff. Parses Retry-After header or seconds in body text.
    private func getWithBackoff(_ url: URL, maxRetries: Int = 5) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        var lastError: Error?
        while attempt <= maxRetries {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if http.statusCode == 429 {
                    // Try Retry-After header; else parse body; else exponential fallback
                    let retryAfterHeader = http.value(forHTTPHeaderField: "Retry-After")
                    var waitMs: UInt64? = nil
                    if let ra = retryAfterHeader, let secs = Double(ra) { waitMs = UInt64(secs * 1000) }
                    if waitMs == nil, let body = String(data: data, encoding: .utf8) {
                        // Look for "retry after X seconds"
                        if let range = body.range(of: "retry after ") {
                            let after = body[range.upperBound...]
                            let digits = after.prefix { $0.isNumber }
                            if let secs = Double(digits) { waitMs = UInt64(secs * 1000) }
                        }
                    }
                    let backoffMs = waitMs ?? UInt64(pow(2.0, Double(attempt)) * 500)
                    let capped = min(backoffMs, 10_000)
                    try? await Task.sleep(nanoseconds: capped * 1_000_000)
                    attempt += 1
                    continue
                }
                return (data, http)
            } catch {
                lastError = error
                // Small retry for transient network failures
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 300) * 1_000_000)
                attempt += 1
            }
        }
        throw lastError ?? URLError(.cannotLoadFromNetwork)
    }

    // Fetch features for one track ID
    func getAudioFeatures(trackId: String) async throws -> ReccoBeatsAudioFeatures {
        // Docs: supports Spotify IDs for multi-track queries and resource resolving
        // Endpoint per docs: GET /v1/track/:id/audio-features
        guard let url = URL(string: "\(baseURL)/v1/track/\(trackId)/audio-features") else {
            throw URLError(.badURL)
        }
        // No API key required per docs
        let (data, http) = try await getWithBackoff(url)
        print("RB af url:", url.absoluteString, "status:", http.statusCode)
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "ReccoBeats", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }
        // Try direct decode first (snake → camel supported)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let direct = try? decoder.decode(ReccoBeatsAudioFeatures.self, from: data) { return direct }
        // Fallback: try to find features in common wrappers
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Common nests: { audioFeatures: {...} } or { data: { audioFeatures: {...} } }
            if let af = obj["audioFeatures"] as? [String: Any] { return ReccoBeatsService.mapDictToFeatures(af) }
            if let dataDict = obj["data"] as? [String: Any] {
                if let af = dataDict["audioFeatures"] as? [String: Any] { return ReccoBeatsService.mapDictToFeatures(af) }
                return ReccoBeatsService.mapDictToFeatures(dataDict)
            }
            let candidateKeys = ["audio_features", "audioFeatures", "data", "result"]
            for k in candidateKeys {
                if let dict = obj[k] as? [String: Any] {
                    return ReccoBeatsService.mapDictToFeatures(dict)
                }
            }
            return ReccoBeatsService.mapDictToFeatures(obj)
        }
        throw NSError(domain: "ReccoBeats", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to decode features"])
    }

    static func mapDictToFeatures(_ d: [String: Any]) -> ReccoBeatsAudioFeatures {
        func dval(_ keys: [String]) -> Double? {
            for k in keys { if let v = d[k] as? Double { return v } }
            return nil
        }
        func ival(_ keys: [String]) -> Int? {
            for k in keys {
                if let v = d[k] as? Int { return v }
                if let v = d[k] as? Double { return Int(v) }
            }
            return nil
        }
        return ReccoBeatsAudioFeatures(
            tempo: dval(["tempo", "bpm", "tempoBpm"]),
            energy: dval(["energy"]),
            danceability: dval(["danceability"]),
            valence: dval(["valence", "moodValence"]),
            loudness: dval(["loudness"]),
            key: ival(["key"]),
            mode: ival(["mode"]),
            time_signature: ival(["time_signature", "timeSignature"]) )
    }

    // Resolve Spotify IDs -> ReccoBeats IDs using multi-get endpoint
    // Returns map: spotifyId -> reccoId
    // Per docs, ids param supports up to 40 per request
    func resolveReccoIds(spotifyIds: [String], batchSize: Int = 40) async -> [String: String] {
        guard !spotifyIds.isEmpty else { return [:] }
        var mapping: [String: String] = [:]
        var index = 0
        while index < spotifyIds.count {
            let end = min(index + batchSize, spotifyIds.count)
            let batch = Array(spotifyIds[index..<end])
            // Build CSV per docs (also supports repeated ids, we use CSV)
            let csv = batch.joined(separator: ",")
            func decodeTracks(_ data: Data) {
                if let obj = try? JSONSerialization.jsonObject(with: data) {
                    // The response may be an array or an object containing an array (e.g., data/result/tracks)
                    func handleArray(_ arr: [[String: Any]]) {
                        for (idx, item) in arr.enumerated() {
                            guard let reccoId = item["id"] as? String else { continue }
                            // Prefer explicit spotifyId if present; else map by order per docs (ids array → content array)
                            var sid: String? = item["spotifyId"] as? String
                            if sid == nil, let href = item["href"] as? String, let last = href.split(separator: "/").last { sid = String(last) }
                            if sid == nil, idx < batch.count { sid = batch[idx] }
                            if let sid = sid { mapping[sid] = reccoId }
                        }
                    }
                    if let arr = obj as? [[String: Any]] {
                        handleArray(arr)
                    }
                    else if let dict = obj as? [String: Any] {
                        let keys = ["content", "data", "result", "tracks", "items"]
                        for k in keys {
                            if let arr = dict[k] as? [[String: Any]] {
                                handleArray(arr)
                            }
                        }
                        // Single object shape
                        if let reccoId = dict["id"] as? String {
                            var spotifyId: String? = dict["spotifyId"] as? String
                            if spotifyId == nil, let href = dict["href"] as? String, let last = href.split(separator: "/").last { spotifyId = String(last) }
                            if let sid = spotifyId { mapping[sid] = reccoId }
                        }
                    }
                }
            }

            // Try CSV style first
            if let url = URL(string: "\(baseURL)/v1/track?ids=\(csv)") {
                do {
                    let (data, http) = try await getWithBackoff(url)
                    print("RB resolve url:", url.absoluteString, "status:", http.statusCode)
                    if (200...299).contains(http.statusCode) {
                        decodeTracks(data)
                        if mapping.isEmpty { print("RB resolve 200 but no mapping from csv; body:", String(data: data, encoding: .utf8)?.prefix(300) ?? "") }
                    } else {
                        let body = String(data: data, encoding: .utf8) ?? ""
                        print("RB resolve body snippet:", body.prefix(200))
                    }
                } catch {
                    print("RB resolve error (csv):", error.localizedDescription)
                }
            }

            // If CSV produced no mappings for this batch, try repeated ids style
            let missing = batch.filter { mapping[$0] == nil }
            if !missing.isEmpty {
                var comps = URLComponents(string: "\(baseURL)/v1/track")!
                comps.queryItems = missing.map { URLQueryItem(name: "ids", value: $0) }
                do {
                    let (data2, http2) = try await getWithBackoff(comps.url!)
                    print("RB resolve url:", comps.url!.absoluteString, "status:", http2.statusCode)
                    if (200...299).contains(http2.statusCode) {
                        decodeTracks(data2)
                        if missing.contains(where: { mapping[$0] == nil }) {
                            print("RB resolve 200 but some ids still unmapped; body:", String(data: data2, encoding: .utf8)?.prefix(300) ?? "")
                        }
                    } else {
                        let body = String(data: data2, encoding: .utf8) ?? ""
                        print("RB resolve body snippet (repeated):", body.prefix(200))
                    }
                } catch {
                    print("RB resolve error (repeated):", error.localizedDescription)
                }
            }
            // Gentle pacing between batches
            try? await Task.sleep(nanoseconds: 300_000_000)
            index = end
        }
        return mapping
    }

    // Bulk with limited concurrency via chunking (no custom actors)
    func getAudioFeaturesBulk(ids: [String], maxConcurrency: Int = 8) async -> [String: ReccoBeatsAudioFeatures] {
        guard !ids.isEmpty else { return [:] }
        var result: [String: ReccoBeatsAudioFeatures] = [:]
        let step = max(1, maxConcurrency)
        var index = 0
        while index < ids.count {
            let end = min(index + step, ids.count)
            let batch = Array(ids[index..<end])
            await withTaskGroup(of: (String, ReccoBeatsAudioFeatures)?.self) { group in
                for id in batch {
                    group.addTask { [self] in
                        do { let f = try await getAudioFeatures(trackId: id); return (id, f) }
                        catch { return nil }
                    }
                }
                for await pair in group { if let (id, f) = pair { result[id] = f } }
            }
            // Light pacing between batches
            index = end
            if index < ids.count { try? await Task.sleep(nanoseconds: 50_000_000) }
        }
        return result
    }

    // Bulk fetch using mapping spotifyId -> reccoId; returns features keyed by spotifyId
    func getAudioFeaturesBulkMapped(spToRecco: [String: String], maxConcurrency: Int = 8) async -> [String: ReccoBeatsAudioFeatures] {
        guard !spToRecco.isEmpty else { return [:] }
        var result: [String: ReccoBeatsAudioFeatures] = [:]
        let pairs = Array(spToRecco)
        let step = max(1, maxConcurrency)
        var index = 0
        while index < pairs.count {
            let end = min(index + step, pairs.count)
            let batch = Array(pairs[index..<end])
            await withTaskGroup(of: (String, ReccoBeatsAudioFeatures)?.self) { group in
                for (spotifyId, reccoId) in batch {
                    group.addTask { [self] in
                        do { let f = try await getAudioFeatures(trackId: reccoId); return (spotifyId, f) }
                        catch { return nil }
                    }
                }
                for await pair in group { if let (sid, f) = pair { result[sid] = f } }
            }
            // Light pacing between batches
            index = end
            if index < pairs.count { try? await Task.sleep(nanoseconds: 50_000_000) }
        }
        return result
    }
}



