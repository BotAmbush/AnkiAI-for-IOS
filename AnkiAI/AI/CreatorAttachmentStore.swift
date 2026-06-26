import Foundation
import CryptoKit

/// Metadata for a creator attachment stored as a scoped FILE (Repair 2). The bytes
/// live under Application Support/CreatorSessions/<id>/Attachments/ — never inline
/// in JSON or UserDefaults.
public struct CreatorAttachmentRef: Codable, Equatable, Identifiable {
    public var id: String
    public var filename: String        // generated, unique, no path separators
    public var contentType: String
    public var byteSize: Int
    public var sha256: String
    public var createdAt: Date
    public init(id: String, filename: String, contentType: String, byteSize: Int, sha256: String, createdAt: Date) {
        self.id = id; self.filename = filename; self.contentType = contentType
        self.byteSize = byteSize; self.sha256 = sha256; self.createdAt = createdAt
    }
}

public enum CreatorAttachmentError: Error, Equatable {
    case tooLarge, sessionTooLarge, decodeFailed, writeFailed, missingFile, checksumMismatch, sizeMismatch, pathEscape
}

/// File-backed, validated attachment storage scoped per creator session.
public enum CreatorAttachmentStore {
    public static let maxFileBytes = 20 * 1024 * 1024      // 20 MB / file
    public static let maxSessionBytes = 80 * 1024 * 1024   // 80 MB / session

    private static func base() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
    }

    public static func attachmentsDir(_ sessionId: String) throws -> URL {
        let safe = sessionId.replacingOccurrences(of: "/", with: "_")
        let dir = try base()
            .appendingPathComponent("CreatorSessions", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func ext(for contentType: String) -> String {
        switch contentType.lowercased() {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "application/pdf": return "pdf"
        default: return "bin"
        }
    }

    public static func totalBytes(_ sessionId: String) -> Int {
        guard let dir = try? attachmentsDir(sessionId),
              let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Save a payload as a scoped file with a unique name; returns its metadata ref.
    public static func save(payload: ImagePayload, sessionId: String) throws -> CreatorAttachmentRef {
        guard let data = Data(base64Encoded: payload.base64) else { throw CreatorAttachmentError.decodeFailed }
        guard data.count <= maxFileBytes else { throw CreatorAttachmentError.tooLarge }
        guard totalBytes(sessionId) + data.count <= maxSessionBytes else { throw CreatorAttachmentError.sessionTooLarge }

        let id = UUID().uuidString
        let filename = "\(id).\(ext(for: payload.mediaType))"
        let dir = try attachmentsDir(sessionId)
        let url = dir.appendingPathComponent(filename)
        do { try data.write(to: url, options: .atomic) } catch { throw CreatorAttachmentError.writeFailed }

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return CreatorAttachmentRef(id: id, filename: filename, contentType: payload.mediaType,
                                    byteSize: data.count, sha256: digest, createdAt: Date())
    }

    /// Load + VALIDATE a ref: stays inside the session dir, exists, size + checksum
    /// match. Returns the payload, or throws.
    public static func load(ref: CreatorAttachmentRef, sessionId: String) throws -> ImagePayload {
        // Reject any path separators / traversal in the stored filename.
        guard !ref.filename.contains("/"), !ref.filename.contains("\\"), !ref.filename.contains("..") else {
            throw CreatorAttachmentError.pathEscape
        }
        let dir = try attachmentsDir(sessionId)
        let url = dir.appendingPathComponent(ref.filename)
        guard url.standardizedFileURL.path.hasPrefix(dir.standardizedFileURL.path) else {
            throw CreatorAttachmentError.pathEscape
        }
        guard FileManager.default.fileExists(atPath: url.path), let data = try? Data(contentsOf: url) else {
            throw CreatorAttachmentError.missingFile
        }
        guard data.count == ref.byteSize else { throw CreatorAttachmentError.sizeMismatch }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == ref.sha256 else { throw CreatorAttachmentError.checksumMismatch }
        return ImagePayload(base64: data.base64EncodedString(), mediaType: ref.contentType)
    }

    /// Remove ALL attachment files for a session (and the directory).
    public static func clear(sessionId: String) {
        if let dir = try? attachmentsDir(sessionId) {
            try? FileManager.default.removeItem(at: dir)
        }
    }
}
