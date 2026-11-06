import Foundation

/// Reads organization token usage for the current month via the Admin API usage report.
/// https://docs.claude.com/en/api/admin-api/usage-cost/get-messages-usage-report
struct AnthropicUsageProvider: UsageProvider {
    static let keychainAccount = "anthropic"

    let apiKey: String
    var session: URLSession = .shared
    var baseURL = URL(string: "https://api.anthropic.com")!
    let minimumRefreshInterval: TimeInterval = 60

    func fetchUsage() async throws -> UsageSnapshot {
        let start = Date.startOfCurrentMonthUTC()
        var tokens = TokenUsage()
        var page: String?
        repeat {
            let report = try await fetchPage(start: start, page: page)
            for result in report.data.flatMap(\.results) {
                tokens.inputTokens += result.uncached_input_tokens ?? 0
                tokens.outputTokens += result.output_tokens ?? 0
                tokens.cacheReadTokens += result.cache_read_input_tokens ?? 0
                tokens.cacheCreationTokens += (result.cache_creation?.ephemeral_5m_input_tokens ?? 0)
                    + (result.cache_creation?.ephemeral_1h_input_tokens ?? 0)
            }
            page = report.has_more == true ? report.next_page : nil
        } while page != nil
        return UsageSnapshot(tokens: tokens)
    }

    private func fetchPage(start: Date, page: String?) async throws -> Report {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/organizations/usage_report/messages"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: start.formatted(.iso8601)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31"),
        ]
        if let page { components.queryItems?.append(URLQueryItem(name: "page", value: page)) }

        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await session.data(for: request)
        try UsageError.check(response, data: data)
        do { return try JSONDecoder().decode(Report.self, from: data) } catch { throw UsageError.invalidResponse }
    }

    // Field names mirror the API's snake_case JSON.
    private struct Report: Decodable {
        struct Bucket: Decodable { let results: [Result] }
        struct Result: Decodable {
            struct CacheCreation: Decodable {
                let ephemeral_1h_input_tokens: Int?
                let ephemeral_5m_input_tokens: Int?
            }
            let uncached_input_tokens: Int?
            let output_tokens: Int?
            let cache_read_input_tokens: Int?
            let cache_creation: CacheCreation?
        }
        let data: [Bucket]
        let has_more: Bool?
        let next_page: String?
    }
}
