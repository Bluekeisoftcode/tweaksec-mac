import Foundation

/// ChatGPT Plus/Pro Codex limits via the endpoint behind Codex CLI's `/status`.
/// Undocumented: it may change without notice.
struct CodexUsageProvider: UsageProvider {
    let credentials: CodexCredentials
    var session: URLSession = .shared
    var baseURL = URL(string: "https://chatgpt.com")!
    let minimumRefreshInterval: TimeInterval = 180

    func fetchUsage() async throws -> UsageSnapshot {
        guard !credentials.isExpired else { throw UsageError.credentialsExpired(.codex) }

        var request = URLRequest(url: baseURL.appendingPathComponent("backend-api/wham/usage"), timeoutInterval: 30)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = credentials.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await session.data(for: request)
        do {
            try UsageError.check(response, data: data)
        } catch UsageError.unauthorized {
            throw UsageError.credentialsExpired(.codex)
        }
        guard let body = try? JSONDecoder().decode(Response.self, from: data) else { throw UsageError.invalidResponse }

        // The slots do not name the period; the 5-hour window may be absent, leaving only the weekly one.
        let windows: [(String, Response.Window?)] = [
            ("primary", body.rate_limit?.primary_window),
            ("secondary", body.rate_limit?.secondary_window),
        ]
        return UsageSnapshot(
            planName: body.plan_type.map { "ChatGPT " + $0.prefix(1).uppercased() + $0.dropFirst() },
            windows: windows.compactMap { id, window in
                guard let window else { return nil }
                return UsageWindow(id: id, title: Self.title(forWindowSeconds: window.limit_window_seconds),
                                   percent: window.used_percent,
                                   resetsAt: window.reset_at.map(Date.init(timeIntervalSince1970:)))
            }
        )
    }

    static func title(forWindowSeconds seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "Usage Limit" }
        switch seconds {
        case 604_800: return "Weekly"
        case let s where s % 86_400 == 0: return "\(s / 86_400)-Day"
        default: return "\(Int((Double(seconds) / 3600).rounded()))-Hour Session"
        }
    }

    private struct Response: Decodable {
        struct Window: Decodable {
            let used_percent: Double
            let limit_window_seconds: Int?
            let reset_at: Double?
        }
        struct RateLimit: Decodable {
            let primary_window: Window?
            let secondary_window: Window?
        }
        let plan_type: String?
        let rate_limit: RateLimit?
    }
}
