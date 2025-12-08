import Foundation

/// Service for genre umbrella matching using the JSON mapping.
/// This is a CLI-compatible version of the app's GenreUmbrellaService.
final class GenreUmbrellaService {
    static let shared = GenreUmbrellaService()
    
    // MARK: - Types
    
    struct Umbrella: Codable {
        let id: String
        let keywords: [String]
        let neighbors: [String]
    }
    
    // MARK: - Properties
    
    private(set) var umbrellasById: [String: Umbrella] = [:]
    private(set) var keywordToUmbrellaId: [String: String] = [:]
    private var loaded = false
    
    // MARK: - Loading
    
    /// Load the umbrella mapping from the bundled JSON file
    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        
        let fileManager = FileManager.default
        
        // Try to find the mapping file from various locations
        let possiblePaths = [
            // Relative to current directory (when running from project root)
            fileManager.currentDirectoryPath + "/RunClub/RunClub/Resources/umbrella_genre_mapping.json",
            // Relative to executable location
            (CommandLine.arguments[0] as NSString).deletingLastPathComponent + "/../../../RunClub/RunClub/Resources/umbrella_genre_mapping.json",
            // CLI Resources folder
            (CommandLine.arguments[0] as NSString).deletingLastPathComponent + "/Resources/umbrella_genre_mapping.json",
            // Absolute fallback
            NSHomeDirectory() + "/Documents/RunClubApp/RunClub/RunClub/Resources/umbrella_genre_mapping.json"
        ]
        
        var data: Data?
        for path in possiblePaths {
            let url = URL(fileURLWithPath: path)
            if fileManager.fileExists(atPath: url.path) {
                data = try? Data(contentsOf: url)
                if data != nil {
                    break
                }
            }
        }
        
        guard let jsonData = data else {
            print("Warning: Could not load umbrella_genre_mapping.json")
            return
        }
        
        do {
            let umbrellas = try JSONDecoder().decode([Umbrella].self, from: jsonData)
            for u in umbrellas {
                umbrellasById[u.id] = u
                for kw in u.keywords {
                    keywordToUmbrellaId[kw.lowercased()] = u.id
                }
            }
        } catch {
            print("Warning: Failed to parse umbrella_genre_mapping.json: \(error)")
        }
    }
    
    // MARK: - Matching
    
    /// Get the umbrella ID for a given keyword
    func umbrellaId(for keyword: String) -> String? {
        loadIfNeeded()
        return keywordToUmbrellaId[keyword.lowercased()]
    }
    
    /// Compute affinity score for an artist's genres against target umbrellas
    func affinity(for artistGenres: [String], targetUmbrellaWeights: [String: Double]) -> Double {
        loadIfNeeded()
        guard !targetUmbrellaWeights.isEmpty else { return 0.0 }
        
        var totalAffinity = 0.0
        var matchCount = 0
        
        for genre in artistGenres {
            let lowered = genre.lowercased()
            
            // Check for exact keyword match
            if let matchedUmbrellaId = keywordToUmbrellaId[lowered] {
                if let weight = targetUmbrellaWeights[matchedUmbrellaId] {
                    totalAffinity += weight
                    matchCount += 1
                }
            }
            
            // Check for partial keyword matches
            for (keyword, umbrellaId) in keywordToUmbrellaId {
                if lowered.contains(keyword) || keyword.contains(lowered) {
                    if let weight = targetUmbrellaWeights[umbrellaId] {
                        totalAffinity += weight * 0.5  // Partial match gets half weight
                        matchCount += 1
                    }
                }
            }
        }
        
        // Normalize by number of artist genres to avoid bias toward artists with many genres
        let normalized = matchCount > 0 ? totalAffinity / Double(artistGenres.count) : 0.0
        return min(1.0, normalized)
    }
    
    /// Build weights map for selected umbrellas plus their neighbors
    func selectedWithNeighborsWeights(selectedIds: [String], neighborWeight: Double = 0.6) -> [String: Double] {
        loadIfNeeded()
        var weights: [String: Double] = [:]
        
        // Add selected with full weight
        for id in selectedIds {
            weights[id] = 1.0
        }
        
        // Add neighbors with reduced weight (only if neighborWeight > 0)
        if neighborWeight > 0 {
            for id in selectedIds {
                if let umbrella = umbrellasById[id] {
                    for neighbor in umbrella.neighbors {
                        // Only add if not already selected (don't override full weight)
                        if weights[neighbor] == nil {
                            weights[neighbor] = neighborWeight
                        }
                    }
                }
            }
        }
        
        return weights
    }
}
