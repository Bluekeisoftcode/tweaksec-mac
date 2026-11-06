import Foundation

/// Claude Pro/Max plan limits via the endpoint behind Claude Code's `/usage`.
/// Undocumented: it may change without notice. It only reads metadata, so it costs nothing
/// and does not count toward plan limits, but it is rate limited aggressively.
struct ClaudeSubscriptionUsageProvider: UsageProvider {
    let credentials: ClaudeCodeCredentials
    var session: URLSession = .shared
    var baseURL = URL(string: "https://api.anthropic.com")!
    let minimumRefreshInterval: TimeInterval = 180

    func fetchUsage() async throws -> UsageSnapshot {
        guard !credentials.isExpired else { throw UsageError.credentialsExpired(.claudeCode) }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/oauth/usage"), timeoutInterval: 30)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await session.data(for: request)
        do {
            try UsageError.check(response, data: data)
        } catch UsageError.unauthorized {
            throw UsageError.credentialsExpired(.claudeCode)
        }
        guard let body = try? JSONDecoder().decode(Response.self, from: data) else { throw UsageError.invalidResponse }

        let windows: [(String, String, Response.Window?)] = [
            ("five_hour", "5-Hour Session", body.five_hour),
            ("seven_day", "Weekly (All Models)", body.seven_day),
            ("seven_day_opus", "Weekly Opus", body.seven_day_opus),
            ("seven_day_sonnet", "Weekly Sonnet", body.seven_day_sonnet),
        ]
        return UsageSnapshot(
            planName: credentials.planName,
            windows: windows.compactMap { id, title, window in
                guard let percent = window?.utilization else { return nil }
                return UsageWindow(id: id, title: title, percent: percent,
                                   resetsAt: window?.resets_at.flatMap(Date.iso8601Lenient))
            }
        )
    }

    private struct Response: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resets_at: String?
        }
        let five_hour: Window?
        let seven_day: Window?
        let seven_day_opus: Window?
        let seven_day_sonnet: Window?
    }
}
