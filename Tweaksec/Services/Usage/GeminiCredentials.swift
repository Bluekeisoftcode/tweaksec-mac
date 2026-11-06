import Foundation

/// Gemini CLI's Google login, read-only. The access token lasts about an hour;
/// Gemini CLI refreshes it whenever it runs.
struct GeminiCredentials: Sendable, Equatable {
    let accessToken: String
    let expiresAt: Date?

    var isExpired: Bool { expiresAt.map { $0 <= .now } ?? false }

    static func parse(_ data: Data) -> GeminiCredentials? {
        struct File: Decodable {
            let access_token: String?
            let expiry_date: Double?
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data),
              let token = file.access_token, !token.isEmpty else { return nil }
        return GeminiCredentials(accessToken: token,
                                 expiresAt: file.expiry_date.map { Date(timeIntervalSince1970: $0 / 1000) })
    }

    /// Reads `~/.gemini/oauth_creds.json`, written by "Login with Google".
    static func load() -> GeminiCredentials? {
        let file = UserHome.url.appendingPathComponent(".gemini/oauth_creds.json")
        return (try? Data(contentsOf: file)).flatMap(parse)
    }
}
