import XCTest
@testable import AnkiAI

private struct FakeTransport: HTTPTransport, @unchecked Sendable {
    let handler: (URLRequest) -> (Data, HTTPURLResponse)
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { handler(request) }
}

final class ClaudeAPIClientTests: XCTestCase {

    private func response(_ status: Int, _ body: [String: Any]) -> (Data, HTTPURLResponse) {
        let data = try! JSONSerialization.data(withJSONObject: body)
        let http = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!,
                                   statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, http)
    }

    func testSuccessfulTextExtractionAndUsage() async {
        var capturedHeaders: [String: String]?
        let transport = FakeTransport { req in
            capturedHeaders = req.allHTTPHeaderFields
            return self.response(200, [
                "content": [["type": "text", "text": "Hello!"]],
                "usage": ["input_tokens": 12, "output_tokens": 3],
            ])
        }
        let client = ClaudeAPIClient(apiKey: "sk-ant-x", transport: transport)
        var usage: TokenUsage?
        let result = await client.chat(systemPrompt: "sys", history: [ChatTurn(role: "user", content: "hi")],
                                       dynamicSystemSuffix: "", onTokensUsed: { usage = $0 })
        XCTAssertEqual(try? result.get(), "Hello!")
        XCTAssertEqual(usage?.inputTokens, 12)
        XCTAssertEqual(capturedHeaders?["x-api-key"], "sk-ant-x")
        XCTAssertEqual(capturedHeaders?["anthropic-version"], "2023-06-01")
        // No caching header when no dynamic suffix.
        XCTAssertNil(capturedHeaders?["anthropic-beta"])
    }

    func testCachingHeaderWhenDynamicSuffixPresent() async {
        var headers: [String: String]?
        var bodyJSON: [String: Any]?
        let transport = FakeTransport { req in
            headers = req.allHTTPHeaderFields
            if let body = req.httpBody { bodyJSON = try? JSONSerialization.jsonObject(with: body) as? [String: Any] }
            return self.response(200, ["content": [["type": "text", "text": "ok"]]])
        }
        let client = ClaudeAPIClient(apiKey: "k", transport: transport)
        _ = await client.chat(systemPrompt: "STATIC", history: [ChatTurn(role: "user", content: "x")],
                              dynamicSystemSuffix: "DYNAMIC", onTokensUsed: nil)
        XCTAssertEqual(headers?["anthropic-beta"], "prompt-caching-2024-07-31")
        // system field should be an array with a cache_control breakpoint on the static block.
        let system = bodyJSON?["system"] as? [[String: Any]]
        XCTAssertEqual(system?.count, 2)
        XCTAssertNotNil((system?[0]["cache_control"]))
        XCTAssertEqual(system?[0]["text"] as? String, "STATIC")
        XCTAssertEqual(system?[1]["text"] as? String, "DYNAMIC")
    }

    func testUnauthorizedMapped() async {
        let transport = FakeTransport { _ in self.response(401, ["error": "bad key"]) }
        let client = ClaudeAPIClient(apiKey: "k", transport: transport)
        let result = await client.chat(systemPrompt: "s", history: [])
        if case .failure(let e) = result { XCTAssertEqual(e, .unauthorized) } else { XCTFail("expected failure") }
    }

    func testOverloadedMapped() async {
        let transport = FakeTransport { _ in self.response(529, ["error": "overloaded"]) }
        let client = ClaudeAPIClient(apiKey: "k", transport: transport)
        let result = await client.chat(systemPrompt: "s", history: [])
        if case .failure(let e) = result { XCTAssertEqual(e, .overloaded) } else { XCTFail("expected failure") }
    }

    func testImageMessageShaping() {
        let turns = [ChatTurnWithImage(role: "user", text: "look", images: [ImagePayload(base64: "AAAA", mediaType: "image/jpeg")])]
        let array = ClaudeAPIClient.buildMessagesArray(turns)
        let content = array.first?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 2) // image + text
        XCTAssertEqual(content?[0]["type"] as? String, "image")
        XCTAssertEqual(content?[1]["type"] as? String, "text")
    }
}
