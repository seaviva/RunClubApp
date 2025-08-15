import Foundation

struct SpotifyCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}
