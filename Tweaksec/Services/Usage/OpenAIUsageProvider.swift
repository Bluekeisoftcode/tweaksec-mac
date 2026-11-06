import Foundation

/// Reads organization token usage for the current month via the Usage API.
/// https://platform.openai.com/docs/api-reference/usage/completions
struct OpenAIUsageProvider: UsageProvider {
    static let keychainAccount = "openai"

    let apiKey: String
    var session: URLSession = .shared
    var baseURL = URL(string: "https://api.openai.com")!
    let minimumRefreshInterval: TimeInterval = 60

    func fetchUsage() async throws -> UsageSnapshot {
        let start = Date.startOfCurrentMonthUTC()
        var tokens = TokenUsage()
        var page: String?
        repeat {
            let report = try await fetchPage(start: start, page: page)
            for result in report.data.flatMap(\.results) {
                let cached = result.input_cached_tokens ?? 0
                tokens.inputTokens += (result.input_tokens ?? 0) - cached
                tokens.cacheReadTokens += cached
                tokens.outputTokens += result.output_tokens ?? 0
            }
            page = report.has_more == true ? report.next_page : nil
        } while page != nil
        return UsageSnapshot(tokens: tokens)
    }

    private func fetchPage(start: Date, page: String?) async throws -> Report {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/organization/usage/completions"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31"),
        ]
        if let page { components.queryItems?.append(URLQueryItem(name: "page", value: page)) }

        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try UsageError.check(response, data: data)
        do { return try JSONDecoder().decode(Report.self, from: data) } catch { throw UsageError.invalidResponse }
    }

    // Field names mirror the API's snake_case JSON. `input_tokens` includes cached tokens.
    private struct Report: Decodable {
        struct Bucket: Decodable { let results: [Result] }
        struct Result: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let input_cached_tokens: Int?
        }
        let data: [Bucket]
        let has_more: Bool?
        let next_page: String?
    }
}
