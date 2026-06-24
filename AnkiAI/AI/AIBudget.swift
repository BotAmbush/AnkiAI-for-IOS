import Foundation

/// Token pricing + spend tracking, ported from the constants in `AiChatViewModel`.
/// Prices are USD per token.
public enum AIPricing {
    // Haiku 4.5 — used for reviewer chat
    public static let inputHaiku = 0.0000008   // $0.80 / MTok
    public static let outputHaiku = 0.000004   // $4 / MTok
    // Sonnet 4.6 — used for the card creator
    public static let inputSonnet = 0.000003   // $3 / MTok
    public static let outputSonnet = 0.000015  // $15 / MTok

    public static let defaultBudgetUSD = 20.0

    public static func costHaiku(input: Int, output: Int) -> Double {
        Double(input) * inputHaiku + Double(output) * outputHaiku
    }

    public static func costSonnet(input: Int, output: Int) -> Double {
        Double(input) * inputSonnet + Double(output) * outputSonnet
    }
}

/// Maps low-level client errors to the user-facing messages from `buildErrorMessage`.
public enum AIErrorPresenter {
    public static func message(for error: AIClientError) -> String {
        switch error {
        case .noInternet:
            return "No internet connection."
        case .unauthorized:
            return "Invalid API key. Check your key in Settings → AI Assistant."
        case .rateLimited:
            return "Rate limit reached. Please wait a moment and try again."
        case .overloaded:
            return "Claude is temporarily overloaded. Please try again shortly."
        case .http(let status, let body):
            if body.lowercased().contains("overloaded") {
                return "Claude is temporarily overloaded. Please try again shortly."
            }
            return "Error: HTTP \(status)"
        case .noTextContent:
            return "No text content in Claude response"
        case .malformedResponse:
            return "Could not read Claude response."
        case .underlying(let msg):
            return "Error: \(msg)"
        }
    }
}
