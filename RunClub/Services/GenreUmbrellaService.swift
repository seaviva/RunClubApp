//
//  GenreUmbrellaService.swift
//  RunClub
//
//  Loads umbrella→genres mapping and neighbor relationships from a bundled JSON file
//  and provides affinity computations for artist genres.
//

import Foundation

/// Runtime model for a single umbrella from JSON
struct GenreUmbrella: Codable {
    let id: String
    let display: String
    let genres: [String]
    let neighbors: [String]?
}

/// Top-level JSON container
private struct GenreUmbrellaJSON: Codable {
    let umbrellas: [GenreUmbrella]
}

/// Alternate flexible shapes some user-provided files may use
private struct AltRootSplit: Codable {
    let umbrellas: [String: [String]]?
    let neighbors: [String: [String]]?
    let display: [String: String]?
    let names: [String: String]?
}

/// Alternate shape used by some mapping files where the keys are
///  - umbrella_terms: [display strings]
///  - neighbors: { display: [display] }
///  - mapping: { display: [genres] }
private struct AltRootMapping: Codable {
    let umbrella_terms: [String]?
    let neighbors: [String: [String]]?
    let mapping: [String: [String]]
}

private struct AltUmbrella: Codable {
    let id: String?
    let display: String?
    let name: String?
    let genres: [String]?
    let neighbors: [String]?
}

private enum UmbrellaValue: Codable {
    case object(AltUmbrella)
    case genres([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let arr = try? container.decode([String].self) {
            self = .genres(arr)
            return
        }
        if let obj = try? container.decode(AltUmbrella.self) {
            self = .object(obj)
            return
        }
        throw DecodingError.typeMismatch(UmbrellaValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported umbrella value shape"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .genres(let g): try container.encode(g)
        case .object(let o): try container.encode(o)
        }
    }
}

/// Service that holds umbrella mapping and neighbor relationships.
/// Lazily loads `umbrella_genre_mapping.json` from the main bundle.
final class GenreUmbrellaService {
    static let shared = GenreUmbrellaService()

    private(set) var umbrellasById: [String: GenreUmbrella] = [:]
    private var genreToUmbrellaIds: [String: Set<String>] = [:] // normalized genre → umbrella ids
    private var isLoaded = false

    private init() {}

    /// Load mapping from bundled JSON (idempotent). Falls back to a minimal built-in mapping if file is missing.
    func loadIfNeeded() {
        guard !isLoaded else { return }
        defer { isLoaded = true }

        // Try the expected resource name first
        if let url = Bundle.main.url(forResource: "umbrella_genre_mapping", withExtension: "json") {
            if load(from: url) { return }
        }

        // Also try an alternate name for user-provided files
        if let url2 = Bundle.main.url(forResource: "genre_umbrellas", withExtension: "json") {
            if load(from: url2) { return }
        }

        // Fallback: minimal built-in umbrellas to avoid hard failure during development
        let fallback = GenreUmbrellaJSON(umbrellas: [
            GenreUmbrella(id: "indie", display: "Indie", genres: ["indie rock", "indie pop", "shoegaze", "dream pop", "post punk", "lo-fi", "indietronica"], neighbors: ["rock", "pop"]),
            GenreUmbrella(id: "rock", display: "Rock", genres: ["rock", "alt rock", "classic rock", "garage rock", "punk", "metal", "grunge", "emo"], neighbors: ["indie", "pop"]),
            GenreUmbrella(id: "hiphop", display: "Hip-hop/Rap", genres: ["hip hop", "hip-hop", "rap", "trap", "drill", "grime"], neighbors: ["rnb", "electronic"]),
            GenreUmbrella(id: "electronic", display: "Electronic", genres: ["electronic", "edm", "house", "techno", "trance", "drum and bass", "dnb", "jungle", "dubstep", "garage", "breaks"], neighbors: ["pop", "hiphop"]),
            GenreUmbrella(id: "rnb", display: "R&B", genres: ["r&b", "rnb", "soul", "neo soul", "funk"], neighbors: ["pop", "hiphop"]),
            GenreUmbrella(id: "pop", display: "Pop", genres: ["pop", "dance pop", "synthpop", "electropop"], neighbors: ["rnb", "electronic", "indie"]),
            GenreUmbrella(id: "country", display: "Country", genres: ["country", "alt country", "americana", "folk", "bluegrass"], neighbors: ["indie"])
        ])
        apply(json: fallback)
        print("GenreUmbrellaService: using fallback mapping; add umbrella_genre_mapping.json to bundle for full coverage")
    }

    private func load(from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            try apply(jsonData: data)
            print("GenreUmbrellaService: loaded mapping from \(url.lastPathComponent)")
            return true
        } catch {
            print("GenreUmbrellaService: failed to load bundled mapping: \(error)")
            return false
        }
    }

    private func apply(jsonData: Data) throws {
        let dec = JSONDecoder()
        // 1) Preferred shape: { "umbrellas": [ ... ] }
        if let decoded = try? dec.decode(GenreUmbrellaJSON.self, from: jsonData) {
            apply(json: decoded)
            return
        }
        // 2) Plain array: [ {id, display, genres, neighbors} ]
        if let arr = try? dec.decode([GenreUmbrella].self, from: jsonData) {
            apply(json: GenreUmbrellaJSON(umbrellas: arr))
            return
        }
        // 3) Dictionary: { "rock": {display?, name?, genres:[..], neighbors:[..]}, ... } or { "rock": ["alt rock",..] }
        if let dict = try? dec.decode([String: UmbrellaValue].self, from: jsonData) {
            var list: [GenreUmbrella] = []
            for (key, val) in dict {
                switch val {
                case .genres(let gs):
                    list.append(GenreUmbrella(id: key, display: key.capitalized, genres: gs, neighbors: nil))
                case .object(let o):
                    let disp = o.display ?? o.name ?? key.capitalized
                    let gs = o.genres ?? []
                    list.append(GenreUmbrella(id: key, display: disp, genres: gs, neighbors: o.neighbors))
                }
            }
            apply(json: GenreUmbrellaJSON(umbrellas: list))
            return
        }
        // 4) Split containers: { umbrellas:{id:[genres]}, neighbors:{id:[ids]}, display/names:{id:"Display"} }
        if let split = try? dec.decode(AltRootSplit.self, from: jsonData), let umap = split.umbrellas {
            var list: [GenreUmbrella] = []
            for (key, gs) in umap {
                let disp = split.display?[key] ?? split.names?[key] ?? key.capitalized
                let neigh = split.neighbors?[key]
                list.append(GenreUmbrella(id: key, display: disp, genres: gs, neighbors: neigh))
            }
            apply(json: GenreUmbrellaJSON(umbrellas: list))
            return
        }

        // 5) Alt mapping container: { umbrella_terms:[..], neighbors:{..}, mapping:{ Display:[genres] } }
        if let alt = try? dec.decode(AltRootMapping.self, from: jsonData) {
            var list: [GenreUmbrella] = []
            for (disp, gs) in alt.mapping {
                let neigh = alt.neighbors?[disp]
                // Use the display string as id to keep lookups stable
                list.append(GenreUmbrella(id: disp, display: disp, genres: gs, neighbors: neigh))
            }
            apply(json: GenreUmbrellaJSON(umbrellas: list))
            return
        }

        // If none of the formats matched, throw to let caller log a failure and fall back
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unrecognized umbrella mapping format"))
    }

    private func apply(json: GenreUmbrellaJSON) {
        var byId: [String: GenreUmbrella] = [:]
        var reverse: [String: Set<String>] = [:]
        for u in json.umbrellas {
            byId[u.id] = u
            for g in u.genres {
                let key = GenreUmbrellaService.normalize(g)
                var set = reverse[key] ?? []
                set.insert(u.id)
                reverse[key] = set
            }
        }
        self.umbrellasById = byId
        self.genreToUmbrellaIds = reverse
    }

    /// Returns neighbor weights map including the selected ids with weight 1.0
    /// and first-degree neighbors with weight `neighborWeight` (default 0.6).
    func selectedWithNeighborsWeights(selectedIds: [String], neighborWeight: Double = 0.6) -> [String: Double] {
        loadIfNeeded()
        var weights: [String: Double] = [:]
        for id in selectedIds {
            weights[id] = max(weights[id] ?? 0.0, 1.0)
            if let neigh = umbrellasById[id]?.neighbors {
                for n in neigh { weights[n] = max(weights[n] ?? 0.0, neighborWeight) }
            }
        }
        return weights
    }

    /// Compute a 0–1 affinity of an artist to the target umbrella ids (with weights).
    /// Affinity = (sum of umbrella weights for artist genres that map into those umbrellas) / max(1, artistGenres.count)
    func affinity(for artistGenres: [String], targetUmbrellaWeights: [String: Double]) -> Double {
        loadIfNeeded()
        guard !artistGenres.isEmpty, !targetUmbrellaWeights.isEmpty else { return 0.0 }
        var score: Double = 0.0
        for g in artistGenres {
            let key = GenreUmbrellaService.normalize(g)
            if let ids = genreToUmbrellaIds[key] {
                var best: Double = 0.0
                for id in ids {
                    if let w = targetUmbrellaWeights[id] { best = max(best, w) }
                }
                score += best
            }
        }
        let denom = max(1, artistGenres.count)
        return max(0.0, min(1.0, score / Double(denom)))
    }

    static func normalize(_ g: String) -> String {
        return g.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "&", with: " and ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Bridge from existing UI Genre enum to umbrella ids used by the JSON mapping.
enum GenreUmbrellaBridge {
    static func umbrellaId(for genre: Genre) -> String {
        switch genre {
        case .pop: return "Pop"
        case .hipHopRap: return "Hip-Hop & Rap"
        case .rockAlt: return "Rock & Alt"
        case .electronic: return "Electronic & Dance"
        case .indie: return "Indie"
        case .rnb: return "R&B & Soul"
        case .country: return "Country & Americana"
        case .latin: return "Latin & Reggaeton"
        case .jazzBlues: return "Jazz & Blues"
        case .classicalSoundtrack: return "Classical & Soundtrack"
        }
    }
}


