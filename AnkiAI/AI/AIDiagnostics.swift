import Foundation
import os

/// SANITIZED diagnostics for the AI parsing path (Issue 5). Logs only
/// non-sensitive metadata — never the API key, attachment bytes, or card content.
public enum AIDiagnostics {
    private static let logger = Logger(subsystem: "com.evyatar.ankiai", category: "ai-parse")

    public static func log(stage: String, model: String, responseLength: Int, recovered: Int,
                           stopReason: String? = nil) {
        // %{public}@ is safe: these fields contain no private content.
        logger.info("AI parse — model=\(model, privacy: .public) stage=\(stage, privacy: .public) len=\(responseLength, privacy: .public) recovered=\(recovered, privacy: .public) stop=\(stopReason ?? "n/a", privacy: .public)")
    }
}
