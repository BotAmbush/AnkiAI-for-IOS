import Foundation

/// A single chat turn (text only).
/// Mirrors `ChatTurn` in the Android fork (`ai/api/ClaudeApiClient.kt`).
public struct ChatTurn: Equatable, Sendable {
    public let role: String
    public let content: String
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// A chat turn whose user message may include one or more base64 images.
/// Mirrors `ChatTurnWithImage`.
public struct ChatTurnWithImage: Equatable, Sendable {
    public let role: String
    public let text: String
    /// (base64, mediaType) pairs, e.g. ("...", "image/jpeg")
    public let images: [ImagePayload]
    public init(role: String, text: String, images: [ImagePayload] = []) {
        self.role = role
        self.text = text
        self.images = images
    }
}

public struct ImagePayload: Equatable, Sendable {
    public let base64: String
    public let mediaType: String
    public init(base64: String, mediaType: String) {
        self.base64 = base64
        self.mediaType = mediaType
    }
}

/// Token usage reported by the Messages API.
public struct TokenUsage: Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
}

public enum AIClientError: Error, Equatable {
    case noInternet
    case unauthorized          // 401
    case rateLimited           // 429
    case overloaded            // 529
    case http(status: Int, body: String)
    case noTextContent
    case malformedResponse
    case underlying(String)
}

/// Abstraction over the chat provider so view models can be tested without network.
/// Mirrors the Kotlin `AiChatApiClient` interface.
public protocol AIChatAPIClient: Sendable {
    func chat(
        systemPrompt: String,
        history: [ChatTurn],
        dynamicSystemSuffix: String,
        onTokensUsed: (@Sendable (TokenUsage) -> Void)?
    ) async -> Result<String, AIClientError>

    /// Image-capable variant. Default maps to the text-only `chat` (dropping
    /// images) so test fakes keep working; `ClaudeAPIClient` sends the images.
    func chatWithImages(
        systemPrompt: String,
        history: [ChatTurnWithImage],
        dynamicSystemSuffix: String,
        onTokensUsed: (@Sendable (TokenUsage) -> Void)?
    ) async -> Result<String, AIClientError>
}

public extension AIChatAPIClient {
    func chat(systemPrompt: String, history: [ChatTurn]) async -> Result<String, AIClientError> {
        await chat(systemPrompt: systemPrompt, history: history, dynamicSystemSuffix: "", onTokensUsed: nil)
    }

    /// Default: ignore images, forward the text to `chat`.
    func chatWithImages(
        systemPrompt: String,
        history: [ChatTurnWithImage],
        dynamicSystemSuffix: String,
        onTokensUsed: (@Sendable (TokenUsage) -> Void)?
    ) async -> Result<String, AIClientError> {
        let text = history.map { ChatTurn(role: $0.role, content: $0.text) }
        return await chat(systemPrompt: systemPrompt, history: text,
                          dynamicSystemSuffix: dynamicSystemSuffix, onTokensUsed: onTokensUsed)
    }
}

/// Injectable HTTP transport so the client is unit-testable.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.malformedResponse
        }
        return (data, http)
    }
}

/// Native Swift port of `ClaudeApiClient.kt`.
///
/// Talks to the Anthropic Messages API. When `dynamicSystemSuffix` is non-empty,
/// the static `systemPrompt` block is sent as a cached prefix (`cache_control:
/// ephemeral`, 5-minute TTL) and the dynamic suffix follows uncached — exactly
/// matching the prompt-caching behaviour of the Android fork.
public struct ClaudeAPIClient: AIChatAPIClient {
    public let apiKey: String
    public let model: String
    public let maxTokens: Int
    private let transport: HTTPTransport

    public static let defaultChatModel = "claude-haiku-4-5-20251001"
    public static let defaultCreatorModel = "claude-sonnet-4-6"

    public init(
        apiKey: String,
        model: String = ClaudeAPIClient.defaultChatModel,
        maxTokens: Int = 4096,
        transport: HTTPTransport = URLSessionTransport()
    ) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.transport = transport
    }

    public func chat(
        systemPrompt: String,
        history: [ChatTurn],
        dynamicSystemSuffix: String = "",
        onTokensUsed: (@Sendable (TokenUsage) -> Void)? = nil
    ) async -> Result<String, AIClientError> {
        let turns = history.map { ChatTurnWithImage(role: $0.role, text: $0.content) }
        return await chatWithImages(
            systemPrompt: systemPrompt,
            history: turns,
            dynamicSystemSuffix: dynamicSystemSuffix,
            onTokensUsed: onTokensUsed
        )
    }

    public func chatWithImages(
        systemPrompt: String,
        history: [ChatTurnWithImage],
        dynamicSystemSuffix: String = "",
        onTokensUsed: (@Sendable (TokenUsage) -> Void)? = nil
    ) async -> Result<String, AIClientError> {
        let usingCache = !dynamicSystemSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let systemField: Any
        if usingCache {
            systemField = [
                ["type": "text", "text": systemPrompt,
                 "cache_control": ["type": "ephemeral"]],
                ["type": "text", "text": dynamicSystemSuffix],
            ]
        } else {
            systemField = systemPrompt
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemField,
            "messages": Self.buildMessagesArray(history),
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(.malformedResponse)
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if usingCache {
            request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = bodyData

        do {
            let (data, http) = try await transport.send(request)
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            guard (200..<300).contains(http.statusCode) else {
                return .failure(mapHTTPError(status: http.statusCode, body: bodyString))
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.malformedResponse)
            }
            if let usage = json["usage"] as? [String: Any] {
                let u = TokenUsage(
                    inputTokens: usage["input_tokens"] as? Int ?? 0,
                    outputTokens: usage["output_tokens"] as? Int ?? 0,
                    cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
                    cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0
                )
                onTokensUsed?(u)
            }
            guard let content = json["content"] as? [[String: Any]] else {
                return .failure(.noTextContent)
            }
            for item in content where (item["type"] as? String) == "text" {
                if let text = item["text"] as? String {
                    return .success(text)
                }
            }
            return .failure(.noTextContent)
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet
            || urlError.code == .cannotFindHost || urlError.code == .cannotConnectToHost {
            return .failure(.noInternet)
        } catch {
            return .failure(.underlying("\(error)"))
        }
    }

    static func buildMessagesArray(_ history: [ChatTurnWithImage]) -> [[String: Any]] {
        history.map { turn in
            var content: [[String: Any]] = turn.images.map { img in
                ["type": "image",
                 "source": ["type": "base64", "media_type": img.mediaType, "data": img.base64]]
            }
            content.append(["type": "text", "text": turn.text])
            return ["role": turn.role, "content": content]
        }
    }

    private func mapHTTPError(status: Int, body: String) -> AIClientError {
        switch status {
        case 401: return .unauthorized
        case 429: return .rateLimited
        case 529: return .overloaded
        default: return .http(status: status, body: body)
        }
    }
}
