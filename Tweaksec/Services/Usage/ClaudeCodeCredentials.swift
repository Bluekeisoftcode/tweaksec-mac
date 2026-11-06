import Foundation
import Security

/// Claude Code's OAuth login, read-only. Tweaksec never refreshes the token:
/// refresh tokens rotate, so refreshing here would sign Claude Code out.
struct ClaudeCodeCredentials: Sendable, Equatable {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?

    var isExpired: Bool { expiresAt.map { $0 <= .now } ?? false }

    var planName: String? {
        subscriptionType.map { "Claude " + $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    static func parse(_ data: Data) -> ClaudeCodeCredentials? {
        struct File: Decodable {
            struct OAuth: Decodable {
                let accessToken: String
                let expiresAt: Double?
                let subscriptionType: String?
            }
            let claudeAiOauth: OAuth?
        }
        guard let oauth = (try? JSONDecoder().decode(File.self, from: data))?.claudeAiOauth,
              !oauth.accessToken.isEmpty else { return nil }
        return ClaudeCodeCredentials(accessToken: oauth.accessToken,
                                     expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                                     subscriptionType: oauth.subscriptionType)
    }

    /// Reads the "Claude Code-credentials" Keychain item, falling back to `~/.claude/.credentials.json`.
    /// Outside App Sandbox the `security` tool is used because Claude Code writes the item with it, so it is
    /// already on the item's access list and no Keychain prompt appears. Under App Sandbox the tool inherits
    /// the sandbox, so the item is read directly and macOS may ask the user to allow access.
    static func load() -> ClaudeCodeCredentials? {
        let keychainData = UserHome.isSandboxed ? readKeychainItem() : runSecurity()
        if let data = keychainData, let credentials = parse(data) { return credentials }
        let file = UserHome.url.appendingPathComponent(".claude/.credentials.json")
        return (try? Data(contentsOf: file)).flatMap(parse)
    }

    private static func readKeychainItem() -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "Claude Code-credentials",
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func runSecurity() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
