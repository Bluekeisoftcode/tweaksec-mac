import XCTest
@testable import Tweaksec

final class ClaudeSubscriptionUsageProviderTests: XCTestCase {
    private let sample = Data("""
    {"five_hour":{"utilization":15.0,"resets_at":"2026-09-30T07:20:00.425033+00:00","limit_dollars":null},
     "seven_day":{"utilization":4.0,"resets_at":"2026-10-06T00:00:00.425053+00:00"},
     "seven_day_opus":null,
     "seven_day_sonnet":{"utilization":1.0,"resets_at":"2026-10-06T00:00:00+00:00"},
     "extra_usage":{"is_enabled":false},"limits":[]}
    """.utf8)

    private func provider(expiresIn: TimeInterval = 3600) -> ClaudeSubscriptionUsageProvider {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let credentials = ClaudeCodeCredentials(accessToken: "tok", expiresAt: .now.addingTimeInterval(expiresIn),
                                                subscriptionType: "max")
        return ClaudeSubscriptionUsageProvider(credentials: credentials, session: URLSession(configuration: config))
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
    }

    func testParsesWindows() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/oauth/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
            return (200, [:], self.sample)
        }

        let snapshot = try await provider().fetchUsage()
        XCTAssertEqual(snapshot.planName, "Claude Max")
        XCTAssertNil(snapshot.tokens)
        XCTAssertEqual(snapshot.windows.map(\.id), ["five_hour", "seven_day", "seven_day_sonnet"])
        XCTAssertEqual(snapshot.windows.map(\.percent), [15, 4, 1])
        XCTAssertEqual(snapshot.windows[0].resetsAt, ISO8601DateFormatter().date(from: "2026-09-30T07:20:00Z"))
        XCTAssertEqual(snapshot.windows[2].resetsAt, ISO8601DateFormatter().date(from: "2026-10-06T00:00:00Z"))
    }

    func testUnauthorizedMeansExpiredLogin() async {
        StubURLProtocol.handler = { _ in (401, [:], Data()) }
        do {
            _ = try await provider().fetchUsage()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? UsageError, .credentialsExpired(.claudeCode))
        }
    }

    func testExpiredTokenSkipsRequest() async {
        StubURLProtocol.handler = { _ in
            XCTFail("should not call the endpoint")
            return (200, [:], Data())
        }
        do {
            _ = try await provider(expiresIn: -60).fetchUsage()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? UsageError, .credentialsExpired(.claudeCode))
        }
    }

    func testParsesCredentials() throws {
        let json = Data(#"{"claudeAiOauth":{"accessToken":"abc","refreshToken":"r","expiresAt":1790000000000,"subscriptionType":"pro","scopes":[]},"mcpOAuth":{}}"#.utf8)
        let credentials = try XCTUnwrap(ClaudeCodeCredentials.parse(json))
        XCTAssertEqual(credentials.accessToken, "abc")
        XCTAssertEqual(credentials.expiresAt, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(credentials.planName, "Claude Pro")
        XCTAssertNil(ClaudeCodeCredentials.parse(Data(#"{"mcpOAuth":{}}"#.utf8)))
    }
}
