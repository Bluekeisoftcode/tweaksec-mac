import Foundation

/// A source of usage data. Add a conforming type per AI vendor.
protocol UsageProvider: Sendable {
    /// Shortest allowed polling interval, to stay clear of the endpoint's rate limit.
    var minimumRefreshInterval: TimeInterval { get }
    func fetchUsage() async throws -> UsageSnapshot
}

enum UsageSource: String, CaseIterable, Identifiable, Sendable {
    case claudeSubscription
    case anthropicAdmin
    case openAIAdmin
    case deepSeekBalance
    case codexSubscription
    case geminiCLI

    var id: String { rawValue }
    var title: String {
        switch self {
        case .claudeSubscription: "Claude Subscription (Claude Code Login)"
        case .anthropicAdmin: "Anthropic Admin API"
        case .openAIAdmin: "OpenAI Admin API"
        case .deepSeekBalance: "DeepSeek API Balance"
        case .codexSubscription: "ChatGPT Subscription (Codex Login)"
        case .geminiCLI: "Gemini (Gemini CLI Login)"
        }
    }

    /// Heading shown in the menu when the snapshot has no plan name.
    var menuTitle: String {
        switch self {
        case .claudeSubscription: "Claude Usage"
        case .anthropicAdmin: "Anthropic API Usage"
        case .openAIAdmin: "OpenAI API Usage"
        case .deepSeekBalance: "DeepSeek Balance"
        case .codexSubscription: "Codex Usage"
        case .geminiCLI: "Gemini Usage"
        }
    }

    /// Keychain account for sources configured with an API key; nil for sources that read a CLI login.
    var keychainAccount: String? {
        switch self {
        case .anthropicAdmin: AnthropicUsageProvider.keychainAccount
        case .openAIAdmin: OpenAIUsageProvider.keychainAccount
        case .deepSeekBalance: DeepSeekBalanceProvider.keychainAccount
        case .claudeSubscription, .codexSubscription, .geminiCLI: nil
        }
    }
}

/// A command-line tool whose login is reused to read subscription limits.
enum CLITool: Sendable {
    case claudeCode
    case codex
    case geminiCLI

    var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCLI: "Gemini CLI"
        }
    }

    var command: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex login"
        case .geminiCLI: "gemini"
        }
    }
}

enum UsageError: LocalizedError, Equatable {
    case unauthorized
    case forbidden
    case rateLimited(retryAfter: TimeInterval?)
    case http(status: Int, message: String?)
    case invalidResponse
    case notLoggedIn(CLITool)
    case credentialsExpired(CLITool)
    case homeAccessRequired(CLITool)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Invalid API key."
        case .forbidden: "No permission to read usage. An Admin API key is required."
        case .rateLimited: "Rate limited. Will retry shortly."
        case .http(let status, let message): "Server error (\(status))" + (message.map { ": \($0)" } ?? "")
        case .invalidResponse: "Could not parse the response."
        case .notLoggedIn(let tool): "No \(tool.name) login found. Run `\(tool.command)` in Terminal to log in."
        case .credentialsExpired(let tool): "\(tool.name) token expired. Launch \(tool.name) to refresh it."
        case .homeAccessRequired(let tool): "Grant home folder access from the menu to read the \(tool.name) login."
        }
    }

    /// Maps a non-200 response to an error.
    static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw UsageError.invalidResponse }
        switch http.statusCode {
        case 200: return
        case 401: throw UsageError.unauthorized
        case 403: throw UsageError.forbidden
        case 429:
            throw UsageError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init))
        default:
            struct ErrorBody: Decodable {
                struct Detail: Decodable { let message: String }
                let error: Detail
            }
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
            throw UsageError.http(status: http.statusCode, message: message)
        }
    }
}

extension Date {
    /// First instant of the current month in UTC, matching Console billing periods.
    static func startOfCurrentMonthUTC(now: Date = .now) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
    }

    /// Parses ISO 8601 timestamps with any number of fractional digits (e.g. microseconds).
    static func iso8601Lenient(_ string: String) -> Date? {
        let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
