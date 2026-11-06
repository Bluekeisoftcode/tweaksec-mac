import Foundation

/// Per-model daily request quotas via the Code Assist endpoints behind Gemini CLI's `/stats`.
/// Undocumented: they may change without notice.
struct GeminiUsageProvider: UsageProvider {
    let credentials: GeminiCredentials
    var session: URLSession = .shared
    var baseURL = URL(string: "https://cloudcode-pa.googleapis.com")!
    let minimumRefreshInterval: TimeInterval = 180

    func fetchUsage() async throws -> UsageSnapshot {
        guard !credentials.isExpired else { throw UsageError.credentialsExpired(.geminiCLI) }

        let assist: LoadResponse = try await post("v1internal:loadCodeAssist", body: LoadRequest())
        let quota: QuotaResponse = try await post("v1internal:retrieveUserQuota",
                                                  body: QuotaRequest(project: assist.cloudaicompanionProject))

        let buckets = (quota.buckets ?? []).filter { $0.modelId != nil && $0.remainingFraction != nil }
        return UsageSnapshot(
            planName: assist.currentTier?.name,
            windows: buckets.sorted { $0.modelId! < $1.modelId! }.map { bucket in
                UsageWindow(id: bucket.modelId! + (bucket.tokenType ?? ""), title: bucket.modelId!,
                            percent: (1 - bucket.remainingFraction!) * 100,
                            resetsAt: bucket.resetTime.flatMap(Date.iso8601Lenient))
            }
        )
    }

    private func post<T: Decodable>(_ method: String, body: some Encodable) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(method), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        do {
            try UsageError.check(response, data: data)
        } catch UsageError.unauthorized {
            throw UsageError.credentialsExpired(.geminiCLI)
        }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw UsageError.invalidResponse }
    }

    private struct LoadRequest: Encodable {
        struct Metadata: Encodable {
            let ideType = "IDE_UNSPECIFIED"
            let platform = "PLATFORM_UNSPECIFIED"
            let pluginType = "GEMINI"
        }
        let metadata = Metadata()
    }

    private struct LoadResponse: Decodable {
        struct Tier: Decodable { let name: String? }
        let currentTier: Tier?
        let cloudaicompanionProject: String?
    }

    private struct QuotaRequest: Encodable {
        let project: String?
    }

    private struct QuotaResponse: Decodable {
        struct Bucket: Decodable {
            let modelId: String?
            let tokenType: String?
            let remainingFraction: Double?
            let resetTime: String?
        }
        let buckets: [Bucket]?
    }
}
