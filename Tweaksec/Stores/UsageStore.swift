import Foundation
import Observation

/// Fetches usage only on demand (when the menu opens), never in the background.
@MainActor
@Observable
final class UsageStore {
    enum State: Equatable {
        case idle
        case notConfigured(String)
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastSnapshot: UsageSnapshot?
    /// Whether the current source's API key is saved (always false for CLI-login sources).
    private(set) var hasAPIKey = false

    private let settings: AppSettings
    private let keychain: KeychainStore
    private var isFetching = false
    /// Earliest time the next request may be sent (provider minimum interval or 429 backoff).
    private var nextAllowedFetch: Date = .distantPast

    init(settings: AppSettings, keychain: KeychainStore = KeychainStore()) {
        self.settings = settings
        self.keychain = keychain
        hasAPIKey = apiKey(for: settings.usageSource) != nil
    }

    private func apiKey(for source: UsageSource) -> String? {
        source.keychainAccount.flatMap(keychain.read).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Saves or deletes the API key of the current source.
    func setAPIKey(_ value: String?) {
        guard let account = settings.usageSource.keychainAccount else { return }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            keychain.delete(account)
        } else {
            keychain.write(trimmed, for: account)
        }
        sourceChanged()
    }

    /// Clears data from the previous source and fetches again.
    func sourceChanged() {
        hasAPIKey = apiKey(for: settings.usageSource) != nil
        lastSnapshot = nil
        nextAllowedFetch = .distantPast
        Task { await refresh() }
    }

    /// Fetches unless the endpoint's minimum interval has not elapsed; the cached snapshot is shown meanwhile.
    func refresh() async {
        guard !isFetching, Date.now >= nextAllowedFetch else { return }
        isFetching = true
        defer { isFetching = false }

        let provider: any UsageProvider
        switch await makeProvider() {
        case .success(let value):
            provider = value
        case .failure(let error):
            state = .notConfigured(settings.usageSource.keychainAccount != nil
                                   ? "Enter your \(settings.usageSource.title) key in Settings."
                                   : error.localizedDescription)
            return
        }

        state = .loading
        nextAllowedFetch = .now.addingTimeInterval(provider.minimumRefreshInterval)
        do {
            lastSnapshot = try await provider.fetchUsage()
            state = .loaded
        } catch let error as UsageError {
            state = .failed(error.localizedDescription)
            if case .rateLimited(let retryAfter) = error {
                nextAllowedFetch = .now.addingTimeInterval(max(retryAfter ?? 0, provider.minimumRefreshInterval * 2))
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func makeProvider() async -> Result<any UsageProvider, UsageError> {
        switch settings.usageSource {
        case .claudeSubscription:
            let credentials = await Task.detached { ClaudeCodeCredentials.load() }.value
            return credentials.map { .success(ClaudeSubscriptionUsageProvider(credentials: $0)) } ?? .failure(.notLoggedIn(.claudeCode))
        case .anthropicAdmin:
            return apiKey(for: .anthropicAdmin).map { .success(AnthropicUsageProvider(apiKey: $0)) } ?? .failure(.unauthorized)
        case .openAIAdmin:
            return apiKey(for: .openAIAdmin).map { .success(OpenAIUsageProvider(apiKey: $0)) } ?? .failure(.unauthorized)
        case .deepSeekBalance:
            return apiKey(for: .deepSeekBalance).map { .success(DeepSeekBalanceProvider(apiKey: $0)) } ?? .failure(.unauthorized)
        case .codexSubscription:
            guard HomeAccess.shared.isGranted else { return .failure(.homeAccessRequired(.codex)) }
            let credentials = await Task.detached { CodexCredentials.load() }.value
            return credentials.map { .success(CodexUsageProvider(credentials: $0)) } ?? .failure(.notLoggedIn(.codex))
        case .geminiCLI:
            guard HomeAccess.shared.isGranted else { return .failure(.homeAccessRequired(.geminiCLI)) }
            let credentials = await Task.detached { GeminiCredentials.load() }.value
            return credentials.map { .success(GeminiUsageProvider(credentials: $0)) } ?? .failure(.notLoggedIn(.geminiCLI))
        }
    }
}
