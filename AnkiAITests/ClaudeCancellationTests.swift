import XCTest
@testable import AnkiAI

/// M2.42 — a cancelled AI request degrades gracefully (mapped error, no crash).
final class ClaudeCancellationTests: XCTestCase {

    private struct ThrowingTransport: HTTPTransport {
        let error: Error
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw error }
    }

    func testCancelledRequestSurfacesGracefully() async {
        let client = ClaudeAPIClient(apiKey: "sk-ant-test",
                                     transport: ThrowingTransport(error: URLError(.cancelled)))
        let result = await client.chat(systemPrompt: "s", history: [ChatTurn(role: "user", content: "hi")])
        guard case .failure(let e) = result else { return XCTFail("expected a failure") }
        // A cancelled URLSession task is reported as a graceful underlying error.
        if case .underlying = e {} else { XCTFail("expected .underlying, got \(e)") }
    }

    func testTaskCancellationDoesNotCrash() async {
        // Cancelling the surrounding Task must not crash the client.
        let client = ClaudeAPIClient(apiKey: "sk-ant-test",
                                     transport: ThrowingTransport(error: CancellationError()))
        let result = await client.chat(systemPrompt: "s", history: [ChatTurn(role: "user", content: "hi")])
        if case .failure = result {} else { XCTFail("expected a failure result") }
    }
}
