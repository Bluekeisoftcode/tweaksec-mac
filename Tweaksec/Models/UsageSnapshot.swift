import Foundation

/// A rate-limit window reported as a percentage, e.g. the 5-hour session or weekly limit.
struct UsageWindow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    /// 0–100 (may exceed 100 when over the limit).
    let percent: Double
    let resetsAt: Date?
}

struct TokenUsage: Equatable, Sendable {
    var inputTokens = 0
    var outputTokens = 0
    var cacheCreationTokens = 0
    var cacheReadTokens = 0

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }
}

/// Prepaid API credit in one currency.
struct UsageBalance: Identifiable, Equatable, Sendable {
    var id: String { currency }
    let currency: String
    let total: Decimal
    let granted: Decimal
    let toppedUp: Decimal
}

struct UsageSnapshot: Equatable, Sendable {
    var planName: String?
    var windows: [UsageWindow] = []
    var tokens: TokenUsage?
    var balances: [UsageBalance] = []
    var fetchedAt: Date = .now
}
