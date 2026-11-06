import XCTest
@testable import Tweaksec

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let (status, headers, data) = Self.handler!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class AnthropicUsageProviderTests: XCTestCase {
    private var provider: AnthropicUsageProvider!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        provider = AnthropicUsageProvider(apiKey: "key", session: URLSession(configuration: config))
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
    }

    private func page(_ tokens: Int, next: String?) -> Data {
        let json = """
        {"data":[{"starting_at":"2026-09-01T00:00:00Z","ending_at":"2026-09-02T00:00:00Z","results":[
          {"uncached_input_tokens":\(tokens),"output_tokens":\(tokens * 2),"cache_read_input_tokens":\(tokens * 3),
           "cache_creation":{"ephemeral_5m_input_tokens":\(tokens),"ephemeral_1h_input_tokens":\(tokens)},
           "server_tool_use":{"web_search_requests":0},"model":null}]}],
         "has_more":\(next != nil),"next_page":\(next.map { "\"\($0)\"" } ?? "null")}
        """
        return Data(json.utf8)
    }

    func testAggregatesAcrossPagesAndSendsHeaders() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
            XCTAssertEqual(query.first { $0.name == "bucket_width" }?.value, "1d")
            let isSecond = query.contains { $0.name == "page" && $0.value == "p2" }
            return (200, [:], self.page(isSecond ? 10 : 100, next: isSecond ? nil : "p2"))
        }

        let tokens = try await provider.fetchUsage().tokens
        let snapshot = try XCTUnwrap(tokens)
        XCTAssertEqual(snapshot.inputTokens, 110)
        XCTAssertEqual(snapshot.outputTokens, 220)
        XCTAssertEqual(snapshot.cacheReadTokens, 330)
        XCTAssertEqual(snapshot.cacheCreationTokens, 220)
        XCTAssertEqual(snapshot.totalTokens, 880)
    }

    func testMapsErrors() async {
        let cases: [(Int, [String: String], UsageError)] = [
            (401, [:], .unauthorized),
            (403, [:], .forbidden),
            (429, ["retry-after": "120"], .rateLimited(retryAfter: 120)),
            (500, [:], .http(status: 500, message: "boom")),
        ]
        for (status, headers, expected) in cases {
            StubURLProtocol.handler = { _ in
                (status, headers, Data(#"{"type":"error","error":{"type":"api_error","message":"boom"}}"#.utf8))
            }
            do {
                _ = try await provider.fetchUsage()
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? UsageError, expected)
            }
        }
    }

    func testStartOfMonthUTC() {
        let date = ISO8601DateFormatter().date(from: "2026-09-30T23:30:00Z")!
        XCTAssertEqual(Date.startOfCurrentMonthUTC(now: date), ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z"))
    }
}
