import Foundation

/// Codex CLI's ChatGPT login, read-only. Like Claude Code, refresh tokens rotate,
/// so refreshing here would sign Codex out.
struct CodexCredentials: Sendable, Equatable {
    let accessToken: String
    let accountID: String?
    let expiresAt: Date?

    var isExpired: Bool { expiresAt.map { $0 <= .now } ?? false }

    static func parse(_ data: Data) -> CodexCredentials? {
        struct File: Decodable {
            struct Tokens: Decodable {
                let access_token: String
                let account_id: String?
            }
            let tokens: Tokens?
        }
        guard let tokens = (try? JSONDecoder().decode(File.self, from: data))?.tokens,
              !tokens.access_token.isEmpty else { return nil }
        return CodexCredentials(accessToken: tokens.access_token, accountID: tokens.account_id,
                                expiresAt: jwtExpiry(tokens.access_token))
    }

    /// Reads `~/.codex/auth.json`. Logins stored in the OS keyring (`cli_auth_credentials_store`) are not supported.
    static func load() -> CodexCredentials? {
        let file = UserHome.url.appendingPathComponent(".codex/auth.json")
        return (try? Data(contentsOf: file)).flatMap(parse)
    }

    /// The access token is a JWT; its `exp` claim tells whether Codex needs to refresh it.
    private static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        struct Claims: Decodable { let exp: Double? }
        guard let data = Data(base64Encoded: payload),
              let exp = (try? JSONDecoder().decode(Claims.self, from: data))?.exp else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
