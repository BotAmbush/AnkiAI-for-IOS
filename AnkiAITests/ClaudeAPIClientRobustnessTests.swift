import XCTest
@testable import AnkiAI

/// M2.41 — robustness of the Claude client against the failure modes CLAUDE.md
/// requires: network errors, rate limiting, generic HTTP errors, and malformed
/// AI responses. Verifies the app degrades gracefully (mapped errors, no crash).
final class ClaudeAPIClientRobustnessTests: XCTestCase {

    private struct StatusTransport: HTTPTransport {
        let status: Int
        let data: Data
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (data, HTTPURLResponse(url: request.url ?? URL(string: "https://x")!,
                                   statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private struct ThrowingTransport: HTTPTransport {
        let error: Error
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw error }
    }

    private func client(_ transport: HTTPTransport) -> ClaudeAPIClient {
        ClaudeAPIClient(apiKey: "sk-ant-test", transport: transport)
    }

    private func run(_ transport: HTTPTransport) async -> Result<String, AIClientError> {
        await client(transport).chat(systemPrompt: "s", history: [ChatTurn(role: "user", content: "hi")])
    }

    func testRateLimitedMapped() async {
        let result = await run(StatusTransport(status: 429, data: Data("{}".utf8)))
        guard case .failure(let e) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(e, .rateLimited)
    }

    func testGenericHTTPErrorMapped() async {
        let result = await run(StatusTransport(status: 500, data: Data("boom".utf8)))
        guard case .failure(let e) = result else { return XCTFail("expected failure") }
        if case .http(let status, _) = e { XCTAssertEqual(status, 500) } else { XCTFail("got \(e)") }
    }

    func testNoInternetMapped() async {
        let result = await run(ThrowingTransport(error: URLError(.notConnectedToInternet)))
        guard case .failure(let e) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(e, .noInternet)
    }

    func testCannotConnectMapsToNoInternet() async {
        let result = await run(ThrowingTransport(error: URLError(.cannotConnectToHost)))
        guard case .failure(let e) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(e, .noInternet)
    }

    func testUnexpectedErrorMapsToUnderlying() async {
        struct Boom: Error {}
        let result = await run(ThrowingTransport(error: Boom()))
        guard case .failure(let e) = result else { return XCTFail("expected failure") }
        if case .underlying = e {} else { XCTFail("got \(e)") }
    }

    func testMalformedJSONBody() async {
        let result = await run(StatusTransport(status: 200, data: Data("not json at all".utf8)))
        guard case .failure(let e) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(e, .malformedResponse)
    }

    func testNoTextContentInResponse() async {
        let body = Data(#"{"content":[{"type":"tool_use","name":"x"}]}"#.utf8)
        let result = await run(StatusTransport(status: 200, data: body))
        guard case .failure(let e) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(e, .noTextContent)
    }
}
