import Foundation

/// Reads the prepaid account balance. DeepSeek has no token usage API, so only the balance is shown.
/// https://api-docs.deepseek.com/api/get-user-balance
struct DeepSeekBalanceProvider: UsageProvider {
    static let keychainAccount = "deepseek"

    let apiKey: String
    var session: URLSession = .shared
    var baseURL = URL(string: "https://api.deepseek.com")!
    let minimumRefreshInterval: TimeInterval = 60

    func fetchUsage() async throws -> UsageSnapshot {
        var request = URLRequest(url: baseURL.appendingPathComponent("user/balance"), timeoutInterval: 30)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try UsageError.check(response, data: data)
        guard let body = try? JSONDecoder().decode(Response.self, from: data) else { throw UsageError.invalidResponse }

        return UsageSnapshot(balances: body.balance_infos.map {
            UsageBalance(currency: $0.currency,
                         total: Decimal(string: $0.total_balance) ?? 0,
                         granted: Decimal(string: $0.granted_balance) ?? 0,
                         toppedUp: Decimal(string: $0.topped_up_balance) ?? 0)
        })
    }

    // Amounts are decimal strings, e.g. "110.00".
    private struct Response: Decodable {
        struct Info: Decodable {
            let currency: String
            let total_balance: String
            let granted_balance: String
            let topped_up_balance: String
        }
        let balance_infos: [Info]
    }
}
